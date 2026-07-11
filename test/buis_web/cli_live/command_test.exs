defmodule BuisWeb.CliLive.CommandTest do
  use BuisWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias BuisWeb.CliLive.Command

  describe "Command.parse/1" do
    test "navigation et actions de base" do
      assert Command.parse(":q") == {:navigate, "/cli"}
      assert Command.parse(":menu") == {:navigate, "/cli"}
      assert Command.parse(":list account") == {:navigate, "/cli/r/account/list/read"}
      assert Command.parse(":new account") == {:navigate, "/cli/r/account/a/open"}
      assert Command.parse(":debug") == :toggle_debug
      assert {:message, _} = Command.parse(":help")
    end

    test "entrées invalides" do
      assert {:message, _} = Command.parse(":list inconnu")
      assert {:message, _} = Command.parse(":wat")
      assert Command.parse("3") == :not_command
      assert Command.parse(":") == :noop
    end
  end

  test "la ligne de commande du menu navigue vers une liste", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/cli")

    {:ok, _subfile, html} =
      view
      |> form(".crt-cmd", %{"cmd" => ":list account"})
      |> render_submit()
      |> follow_redirect(conn)

    assert html =~ "LISTE · Comptes bancaires"
  end
end
