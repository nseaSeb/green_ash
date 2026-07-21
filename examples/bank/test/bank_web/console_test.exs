defmodule BankWeb.ConsoleTest do
  @moduledoc """
  Integration tests for the GreenAsh console mounted via `green_ash "/cli"`:
  they validate the lib <-> host wiring (router macro, on_mount, actor
  session, policies) end to end. The pure logic is tested in the lib.
  """
  use BankWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Bank.Ledger.Account

  defp open_account(holder, deposit) do
    Account
    |> Ash.Changeset.for_create(:open, %{holder: holder, initial_deposit: Decimal.new(deposit)})
    |> Ash.create!()
  end

  defp with_actor(conn, %Account{id: id}) do
    Plug.Test.init_test_session(conn, %{"green_ash_actor" => %{"slug" => "account", "id" => id}})
  end

  test "the menu discovers the exposed resource", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/cli")
    assert html =~ "MAIN MENU"
    assert html =~ "Bank accounts"
  end

  test "domains are read dynamically (config :bank, :ash_domains), not pinned to the router",
       %{conn: conn} do
    # Regression: a domain added AFTER `mix green_ash.install` (or removed
    # from the config) must be reflected immediately, without touching the router.
    original = Application.get_env(:bank, :ash_domains)
    on_exit(fn -> Application.put_env(:bank, :ash_domains, original) end)

    Application.put_env(:bank, :ash_domains, [])
    {:ok, _view, html} = live(conn, "/cli")
    refute html =~ "Bank accounts"
    assert html =~ "no resource exposed"

    Application.put_env(:bank, :ash_domains, original)
    {:ok, _view2, html2} = live(conn, "/cli")
    assert html2 =~ "Bank accounts"
  end

  test "creation via the generic screen", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/cli/r/account/a/open")

    view
    |> form("form[phx-submit='submit']", form: %{"holder" => "Bob", "initial_deposit" => "50"})
    |> render_submit()

    assert Enum.any?(Ash.read!(Account, authorize?: false), &(&1.holder == "Bob"))
  end

  test ":list command navigates to the list", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/cli")

    {:ok, _v, html} =
      view
      |> form(".crt-cmd", %{"cmd" => ":list account"})
      |> render_submit()
      |> follow_redirect(conn)

    assert html =~ "LIST · Bank accounts"
  end

  test "deletion: forbidden without an actor, allowed with one (policy + session)", %{conn: conn} do
    acc = open_account("Alice", "10")

    {:ok, view, _html} = live(conn, "/cli/r/account/list/read")
    view |> form("form[phx-submit='process']", %{"opt" => %{acc.id => "4"}}) |> render_submit()
    html = view |> element("button", "Confirm") |> render_click()
    assert html =~ "Forbidden"
    assert {:ok, _} = Ash.get(Account, acc.id, authorize?: false)

    actor = open_account("Chef", "0")
    {:ok, view2, _html} = live(with_actor(conn, actor), "/cli/r/account/list/read")
    view2 |> form("form[phx-submit='process']", %{"opt" => %{acc.id => "4"}}) |> render_submit()
    view2 |> element("button", "Confirm") |> render_click()
    assert match?({:error, _}, Ash.get(Account, acc.id, authorize?: false))
  end

  test "actor set via the controller, reflected in the header", %{conn: conn} do
    acc = open_account("Chef", "0")

    conn = get(conn, "/cli/actor?slug=account&id=#{acc.id}&return=/cli")
    assert redirected_to(conn) == "/cli"

    {:ok, _view, html} = live(recycle(conn), "/cli")
    assert html =~ "Account:"
  end

  test "belongs_to relationship: the account is picked from a list, not typed as a UUID",
       %{conn: conn} do
    {:ok, _view, menu_html} = live(conn, "/cli")
    assert menu_html =~ "Transactions"

    acc = open_account("Alice", "100")

    {:ok, view, html} = live(conn, "/cli/r/transaction/a/create")

    # The foreign key is a choice of real records now. It used to render as a
    # text box wanting a raw id, which meant leaving the console to find one.
    assert html =~ ~s(<select id="form_account_id")
    assert html =~ "Alice"
    assert html =~ String.slice(acc.id, 0, 8)
    refute html =~ ~s(type="text" id="form_account_id")

    view
    |> form("form[phx-submit='submit']", form: %{"account_id" => acc.id, "amount" => "42"})
    |> render_submit()

    assert Enum.any?(
             Ash.read!(Bank.Ledger.Transaction, authorize?: false),
             &(&1.account_id == acc.id and Decimal.equal?(&1.amount, Decimal.new("42")))
           )
  end

  describe "a read Ash insists on paginating" do
    # `:recent` declares `keyset?: true, offset?: false, required?: true`. Ash
    # refuses such a read without page options — the console used to reach it
    # with a plain limit/offset and take the whole screen down. ETS is too
    # permissive to test this; Postgres is what users run.
    setup do
      for n <- 1..25 do
        open_account("H#{String.pad_leading(to_string(n), 2, "0")}", "0")
      end

      :ok
    end

    defp holders(html), do: ~r/H\d\d/ |> Regex.scan(html) |> List.flatten() |> Enum.uniq()

    test "the list opens instead of crashing", %{conn: conn} do
      assert {:ok, _view, html} = live(conn, "/cli/r/account/list/recent")

      assert html =~ "LIST · Bank accounts"
      assert length(holders(html)) == 20
    end

    test "paging walks the whole set, without gaps or repeats", %{conn: conn} do
      {:ok, view, html} = live(conn, "/cli/r/account/list/recent")
      first = holders(html)

      second = view |> element("button[phx-value-dir=next]") |> render_click() |> holders()

      assert first -- (first -- second) == [], "a record appeared on both pages"
      assert length(Enum.uniq(first ++ second)) == 25, "records were skipped between pages"
    end
  end

  describe "the screen lives in the URL" do
    setup do
      for n <- 1..25, do: open_account("H#{String.pad_leading(to_string(n), 2, "0")}", "#{n}")
      :ok
    end

    test "a pasted link reproduces filter, sort and page", %{conn: conn} do
      {:ok, _view, html} =
        live(conn, "/cli/r/account/list/search?filter[holder]=H2&sort=balance:desc&page=1")

      # H2, H20..H25 sorted by balance desc: H25 first.
      assert html =~ "H25"
      refute html =~ "H19"
    end

    test "clicking a column header puts the sort in the address bar", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/cli/r/account/list/read")

      view |> element("th", "Holder") |> render_click()

      assert_patched(view, "/cli/r/account/list/read?sort=holder%3Aasc")
    end

    test "paging is a patch, and going back returns the first page", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/cli/r/account/list/read")

      view |> element("button[phx-value-dir=next]") |> render_click()
      assert_patched(view, "/cli/r/account/list/read?page=2")

      view |> element("button[phx-value-dir=prev]") |> render_click()
      assert_patched(view, "/cli/r/account/list/read")
    end
  end
end
