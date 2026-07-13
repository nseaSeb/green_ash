defmodule BankWeb.PageController do
  use BankWeb, :controller

  def home(conn, _params) do
    # In dev, the root leads directly to the CLI console.
    if Application.get_env(:bank, :dev_routes) do
      redirect(conn, to: "/cli")
    else
      render(conn, :home)
    end
  end
end
