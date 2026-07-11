defmodule BuisWeb.PageController do
  use BuisWeb, :controller

  def home(conn, _params) do
    # En dev, la racine mène directement à la console CLI.
    if Application.get_env(:buis, :dev_routes) do
      redirect(conn, to: "/cli")
    else
      render(conn, :home)
    end
  end
end
