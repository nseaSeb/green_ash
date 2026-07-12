defmodule BuisWeb.CliActorController do
  @moduledoc """
  Écrit/efface l'acteur de la console en session, puis redirige.
  Sollicité par la commande `:actor` des LiveViews (qui ne peuvent pas écrire
  la session via le socket).
  """
  use BuisWeb, :controller

  alias BuisWeb.Cli.Actor

  def set(conn, params) do
    return = params["return"] || "/cli"

    conn =
      case params do
        %{"slug" => slug, "id" => id} when slug != "" and id != "" ->
          put_session(conn, Actor.session_key(), %{"slug" => slug, "id" => id})

        _ ->
          delete_session(conn, Actor.session_key())
      end

    redirect(conn, to: return)
  end
end
