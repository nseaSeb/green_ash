defmodule BuisWeb.CliLive.SubfileTest do
  use BuisWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Buis.Bank.Account

  defp open_account(holder, deposit) do
    Account
    |> Ash.Changeset.for_create(:open, %{holder: holder, initial_deposit: Decimal.new(deposit)})
    |> Ash.create!()
  end

  @list "/cli/r/account/list/read"

  test "le subfile liste les enregistrements de la read action", %{conn: conn} do
    open_account("Alice", "100")
    open_account("Bob", "250")

    {:ok, _view, html} = live(conn, @list)

    assert html =~ "LISTE"
    assert html =~ "Alice"
    assert html =~ "Bob"
    # La légende des codes est dérivée par introspection.
    assert html =~ "Créditer"
    assert html =~ "Supprimer"
  end

  test "l'option 2 (update) ouvre l'écran et crédite l'enregistrement", %{conn: conn} do
    acc = open_account("Alice", "100")

    {:ok, view, _html} = live(conn, @list)

    {:ok, screen, _html} =
      view
      |> form("form[phx-submit='process']", %{"opt" => %{acc.id => "2"}})
      |> render_submit()
      |> follow_redirect(conn)

    screen |> form("form[phx-submit='submit']", form: %{"amount" => "50"}) |> render_submit()

    updated = Ash.get!(Account, acc.id)
    assert Decimal.equal?(updated.balance, Decimal.new("150"))
  end

  test "l'option 4 (destroy) supprime l'enregistrement", %{conn: conn} do
    acc = open_account("Alice", "100")

    {:ok, view, _html} = live(conn, @list)

    view |> form("form[phx-submit='process']", %{"opt" => %{acc.id => "4"}}) |> render_submit()

    assert match?({:error, _}, Ash.get(Account, acc.id))
  end

  test "l'option 5 (afficher) déplie le détail de l'enregistrement", %{conn: conn} do
    open_account("Alice", "100")
    [acc] = Ash.read!(Account)

    {:ok, view, _html} = live(conn, @list)

    html = view |> form("form[phx-submit='process']", %{"opt" => %{acc.id => "5"}}) |> render_submit()

    assert html =~ "affichage"
    # Le détail inspecté contient le module de la resource.
    assert html =~ "Buis.Bank.Account"
  end
end
