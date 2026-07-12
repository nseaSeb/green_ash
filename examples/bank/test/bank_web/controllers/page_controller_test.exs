defmodule BankWeb.PageControllerTest do
  use BankWeb.ConnCase

  test "GET / redirige vers la console CLI en dev", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == "/cli"
  end
end
