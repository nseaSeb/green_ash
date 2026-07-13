defmodule GreenAsh.ActorController do
  @moduledoc """
  Writes/clears the console's actor in the session, then redirects.
  Invoked by the `:actor` command of the LiveViews (which cannot write the
  session via the socket).
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
