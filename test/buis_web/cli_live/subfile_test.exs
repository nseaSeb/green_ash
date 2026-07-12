defmodule BuisWeb.CliLive.SubfileTest do
  use BuisWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Buis.Bank.Account

  defp open_account(holder, deposit) do
    Account
    |> Ash.Changeset.for_create(:open, %{holder: holder, initial_deposit: Decimal.new(deposit)})
    |> Ash.create!()
  end

  defp with_actor(conn, %Account{id: id}) do
    Plug.Test.init_test_session(conn, %{"cli_actor" => %{"slug" => "account", "id" => id}})
  end

  @list "/cli/r/account/list/read"

  test "le subfile liste les enregistrements de la read action", %{conn: conn} do
    open_account("Alice", "100")
    open_account("Bob", "250")

    {:ok, _view, html} = live(conn, @list)

    assert html =~ "LISTE"
    assert html =~ "Alice"
    assert html =~ "Bob"
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

    updated = Ash.get!(Account, acc.id, authorize?: false)
    assert Decimal.equal?(updated.balance, Decimal.new("150"))
  end

  test "l'option 4 avec acteur : confirmation puis suppression", %{conn: conn} do
    actor = open_account("Chef", "0")
    acc = open_account("Alice", "100")

    {:ok, view, _html} = live(with_actor(conn, actor), @list)

    html =
      view
      |> form("form[phx-submit='process']", %{"opt" => %{acc.id => "4"}})
      |> render_submit()

    assert html =~ "Confirmer la suppression"
    assert {:ok, _} = Ash.get(Account, acc.id, authorize?: false)

    view |> element("button", "Confirmer") |> render_click()

    assert match?({:error, _}, Ash.get(Account, acc.id, authorize?: false))
  end

  test "l'option 4 sans acteur est refusée par la policy", %{conn: conn} do
    acc = open_account("Alice", "100")

    {:ok, view, _html} = live(conn, @list)

    view |> form("form[phx-submit='process']", %{"opt" => %{acc.id => "4"}}) |> render_submit()
    html = view |> element("button", "Confirmer") |> render_click()

    assert html =~ "Interdit"
    assert {:ok, _} = Ash.get(Account, acc.id, authorize?: false)
  end

  test "annuler la confirmation ne supprime pas", %{conn: conn} do
    actor = open_account("Chef", "0")
    acc = open_account("Alice", "100")

    {:ok, view, _html} = live(with_actor(conn, actor), @list)

    view |> form("form[phx-submit='process']", %{"opt" => %{acc.id => "4"}}) |> render_submit()
    view |> element("button", "Annuler") |> render_click()

    assert {:ok, _} = Ash.get(Account, acc.id, authorize?: false)
  end

  test "l'option 5 (afficher) déplie le détail de l'enregistrement", %{conn: conn} do
    open_account("Alice", "100")
    [acc] = Ash.read!(Account, authorize?: false)

    {:ok, view, _html} = live(conn, @list)

    html =
      view |> form("form[phx-submit='process']", %{"opt" => %{acc.id => "5"}}) |> render_submit()

    assert html =~ "affichage"
    assert html =~ "Buis.Bank.Account"
  end

  test "la barre de filtre (read :search) filtre côté requête", %{conn: conn} do
    open_account("Alice", "1")
    open_account("Bob", "1")

    {:ok, view, html} = live(conn, "/cli/r/account/list/search")
    assert html =~ "Alice"
    assert html =~ "Bob"
    assert html =~ "Filtre"

    filtered =
      view
      |> form("form.crt-filter", %{"filter" => %{"holder" => "Ali"}})
      |> render_change()

    assert filtered =~ "Alice"
    refute filtered =~ "Bob"
  end

  test "pagination : 20 par page, navigation Suiv/Préc", %{conn: conn} do
    for i <- 1..25, do: open_account("Acc#{String.pad_leading("#{i}", 2, "0")}", "1")

    {:ok, view, html} = live(conn, @list)
    assert row_count(html) == 20
    assert html =~ "Page 1"

    page2 = view |> element("button", "Suiv") |> render_click()
    assert row_count(page2) == 5
    assert page2 =~ "Page 2"

    page1 = view |> element("button", "Préc") |> render_click()
    assert row_count(page1) == 20
    assert page1 =~ "Page 1"
  end

  test "tri par colonne (Holder) : asc puis desc", %{conn: conn} do
    open_account("Charlie", "1")
    open_account("Alice", "1")
    open_account("Bob", "1")

    {:ok, view, _html} = live(conn, @list)

    asc = view |> element("th", "Holder") |> render_click()
    assert pos(asc, "Alice") < pos(asc, "Bob")
    assert pos(asc, "Bob") < pos(asc, "Charlie")

    desc = view |> element("th", "Holder") |> render_click()
    assert pos(desc, "Charlie") < pos(desc, "Alice")
  end

  # Nombre de lignes de données = nombre de champs "Opt" rendus.
  defp row_count(html), do: length(String.split(html, ~s(name="opt[))) - 1

  # Position (octet) de la 1re occurrence d'une chaîne dans le html.
  defp pos(html, s), do: html |> String.split(s) |> hd() |> byte_size()
end
