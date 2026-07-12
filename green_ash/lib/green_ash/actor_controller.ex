defmodule GreenAsh.ActorController do
  @moduledoc """
  Écrit/efface l'acteur de la console en session, puis redirige.
  Sollicité par la commande `:actor` des LiveViews (qui ne peuvent pas écrire la
  session via le socket).
  """
  use Phoenix.Controller, formats: [:html]
  import Plug.Conn

  alias GreenAsh.Actor

  def set(conn, params) do
    return = params["return"] || "/"

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
