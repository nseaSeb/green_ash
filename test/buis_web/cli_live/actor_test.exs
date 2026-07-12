defmodule BuisWeb.CliActorTest do
  use BuisWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Buis.Bank.Account

  defp open_account(holder) do
    Account
    |> Ash.Changeset.for_create(:open, %{holder: holder, initial_deposit: Decimal.new("0")})
    |> Ash.create!()
  end

  test "définir puis effacer l'acteur via le contrôleur, reflété dans l'en-tête", %{conn: conn} do
    acc = open_account("Chef")

    # Définition de l'acteur -> session -> redirection.
    conn = get(conn, "/cli/actor?slug=account&id=#{acc.id}&return=/cli")
    assert redirected_to(conn) == "/cli"

    {:ok, _view, html} = live(recycle(conn), "/cli")
    assert html =~ "Account:"
    refute html =~ "anonyme"

    # Effacement.
    cleared = get(recycle(conn), "/cli/actor?return=/cli")
    {:ok, _view2, html2} = live(recycle(cleared), "/cli")
    assert html2 =~ "anonyme"
  end
end
