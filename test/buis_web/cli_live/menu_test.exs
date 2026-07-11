defmodule BuisWeb.CliLive.MenuTest do
  use BuisWeb.ConnCase

  import Phoenix.LiveViewTest

  test "le menu principal découvre les resources automatiquement", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/cli")

    assert html =~ "MENU PRINCIPAL"
    assert html =~ "Account"
    assert html =~ "Option ==="
  end

  test "sélectionner une resource affiche le menu de ses actions", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/cli")

    html = view |> form(".crt-cmd", %{"cmd" => "1"}) |> render_submit()

    # Les actions de Account, découvertes par introspection.
    assert html =~ "MENU · Account"
    assert html =~ "open"
    assert html =~ "credit"
    assert html =~ "create"
  end

  test "choisir une action create ouvre l'écran de saisie", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/cli")

    # 1 -> Account, puis la position de l'action :open dans la liste.
    view |> form(".crt-cmd", %{"cmd" => "1"}) |> render_submit()

    {:ok, screen, html} =
      view
      |> element(~s(.crt-opt[phx-value-n]), "open")
      |> render_click()
      |> follow_redirect(conn)

    assert html =~ "BUIS / ACCOUNT"
    assert has_element?(screen, ~s(input[name="form[holder]"]))
  end
end
