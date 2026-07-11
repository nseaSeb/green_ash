defmodule BuisWeb.CliLive.ScreenTest do
  use BuisWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Buis.Bank.Account

  @path "/cli/r/account/a/open"

  test "génère l'écran d'action par introspection", %{conn: conn} do
    {:ok, _view, html} = live(conn, @path)

    assert html =~ "BUIS / ACCOUNT"
    assert html =~ "open"
    assert html =~ "create"
    # Widgets déduits des types Ash.
    assert html =~ ~s(name="form[holder]")
    assert html =~ ~s(type="date")
    assert html =~ ~s(name="form[initial_deposit]")
  end

  test "exécute l'action métier et crée l'enregistrement", %{conn: conn} do
    before = length(Ash.read!(Account))

    {:ok, view, _html} = live(conn, @path)

    html =
      view
      |> form("form[phx-submit='submit']",
        form: %{
          "holder" => "Bob",
          "opened_on" => "2026-07-11",
          "initial_deposit" => "250.00"
        }
      )
      |> render_submit()

    assert html =~ "OK"

    accounts = Ash.read!(Account)
    assert length(accounts) == before + 1
    created = Enum.find(accounts, &(&1.holder == "Bob"))
    assert created
    assert Decimal.equal?(created.balance, Decimal.new("250.00"))
  end

  test "affiche les erreurs de validation sans planter", %{conn: conn} do
    {:ok, view, _html} = live(conn, @path)

    html =
      view
      |> form("form[phx-submit='submit']", form: %{"holder" => "", "initial_deposit" => "10"})
      |> render_submit()

    assert html =~ "ACCOUNT"
    refute html =~ "✔ OK"
  end

  test "un slug inconnu renvoie au menu", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/cli"}}} = live(conn, "/cli/r/inconnu/a/open")
  end
end
