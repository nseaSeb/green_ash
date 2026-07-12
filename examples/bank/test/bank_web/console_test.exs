defmodule BankWeb.ConsoleTest do
  @moduledoc """
  Tests d'intégration de la console GreenAsh montée via `green_ash "/cli"` :
  ils valident le câblage lib <-> hôte (macro de routeur, on_mount, session
  d'acteur, policies) de bout en bout. La logique pure est testée dans la lib.
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

  test "le menu découvre la resource exposée", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/cli")
    assert html =~ "MENU PRINCIPAL"
    assert html =~ "Comptes bancaires"
  end

  test "les domaines sont lus dynamiquement (config :bank, :ash_domains), pas figés au routeur",
       %{conn: conn} do
    # Régression : un domaine ajouté APRÈS `mix green_ash.install` (ou retiré
    # de la config) doit se refléter immédiatement, sans toucher au routeur.
    original = Application.get_env(:bank, :ash_domains)
    on_exit(fn -> Application.put_env(:bank, :ash_domains, original) end)

    Application.put_env(:bank, :ash_domains, [])
    {:ok, _view, html} = live(conn, "/cli")
    refute html =~ "Comptes bancaires"
    assert html =~ "aucune resource exposée"

    Application.put_env(:bank, :ash_domains, original)
    {:ok, _view2, html2} = live(conn, "/cli")
    assert html2 =~ "Comptes bancaires"
  end

  test "création via l'écran générique", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/cli/r/account/a/open")

    view
    |> form("form[phx-submit='submit']", form: %{"holder" => "Bob", "initial_deposit" => "50"})
    |> render_submit()

    assert Enum.any?(Ash.read!(Account, authorize?: false), &(&1.holder == "Bob"))
  end

  test "commande :list navigue vers la liste", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/cli")

    {:ok, _v, html} =
      view
      |> form(".crt-cmd", %{"cmd" => ":list account"})
      |> render_submit()
      |> follow_redirect(conn)

    assert html =~ "LISTE · Comptes bancaires"
  end

  test "suppression : interdite sans acteur, autorisée avec (policy + session)", %{conn: conn} do
    acc = open_account("Alice", "10")

    {:ok, view, _html} = live(conn, "/cli/r/account/list/read")
    view |> form("form[phx-submit='process']", %{"opt" => %{acc.id => "4"}}) |> render_submit()
    html = view |> element("button", "Confirmer") |> render_click()
    assert html =~ "Interdit"
    assert {:ok, _} = Ash.get(Account, acc.id, authorize?: false)

    actor = open_account("Chef", "0")
    {:ok, view2, _html} = live(with_actor(conn, actor), "/cli/r/account/list/read")
    view2 |> form("form[phx-submit='process']", %{"opt" => %{acc.id => "4"}}) |> render_submit()
    view2 |> element("button", "Confirmer") |> render_click()
    assert match?({:error, _}, Ash.get(Account, acc.id, authorize?: false))
  end

  test "acteur défini via le contrôleur, reflété dans l'en-tête", %{conn: conn} do
    acc = open_account("Chef", "0")

    conn = get(conn, "/cli/actor?slug=account&id=#{acc.id}&return=/cli")
    assert redirected_to(conn) == "/cli"

    {:ok, _view, html} = live(recycle(conn), "/cli")
    assert html =~ "Account:"
  end

  test "relation belongs_to : le menu liste Transaction, account_id se rend en texte, création OK",
       %{conn: conn} do
    {:ok, _view, menu_html} = live(conn, "/cli")
    assert menu_html =~ "Transactions"

    acc = open_account("Alice", "100")

    {:ok, view, html} = live(conn, "/cli/r/transaction/a/create")
    # Ash.Type.UUID doit se rendre en champ texte, pas en fallback textarea/JSON.
    assert html =~ ~s(type="text" id="form_account_id" name="form[account_id]")

    view
    |> form("form[phx-submit='submit']", form: %{"account_id" => acc.id, "amount" => "42"})
    |> render_submit()

    assert Enum.any?(
             Ash.read!(Bank.Ledger.Transaction, authorize?: false),
             &(&1.account_id == acc.id and Decimal.equal?(&1.amount, Decimal.new("42")))
           )
  end
end
