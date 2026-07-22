defmodule GreenAsh.SessionController do
  @moduledoc """
  Writes/clears the console's actor and tenant in the session, then redirects.

  Invoked by the `:actor` and `:tenant` commands. A LiveView cannot write the
  session through its socket, so both take the long way round: a plain request
  that sets the session and sends you back where you came from.
  """
  use Phoenix.Controller, formats: [:html]
  import Plug.Conn

  alias GreenAsh.{Actor, Tenant}

  def actor(conn, params) do
    case params do
      %{"slug" => slug, "id" => id} when slug != "" and id != "" ->
        put_session(conn, Actor.session_key(), %{"slug" => slug, "id" => id})

      _ ->
        delete_session(conn, Actor.session_key())
    end
    |> back_to(params)
  end

  def tenant(conn, params) do
    case params do
      %{"value" => value} when value != "" -> put_session(conn, Tenant.session_key(), value)
      _ -> delete_session(conn, Tenant.session_key())
    end
    |> back_to(params)
  end

  defp back_to(conn, params), do: redirect(conn, to: params["return"] || "/")
end
