defmodule GreenAsh.OnMount do
  @moduledoc """
  `on_mount` set by the router macro: injects into each LiveView the list of
  domains, the mount base, and the current actor (resolved from the session).

  Without an explicit `domains:` passed to the macro, the list is read **on
  every request** from `Application.get_env(otp_app, :ash_domains, [])` — a
  domain added afterward (via the Ash generators, which already maintain this
  config) therefore appears immediately, with no reinstallation needed.
  """
  import Phoenix.Component, only: [assign: 2]

  def on_mount(:default, _params, session, socket) do
    config = session["green_ash"] || %{}
    domains = domains(config)
    base = Map.get(config, "base", "/")

    {:cont,
     assign(socket,
       domains: domains,
       base: base,
       actor: GreenAsh.Actor.from_session(session, domains)
     )}
  end

  defp domains(%{"domains" => list}) when is_list(list),
    do: Enum.map(list, &String.to_existing_atom/1)

  defp domains(%{"otp_app" => otp_app}) when is_binary(otp_app) do
    otp_app |> String.to_existing_atom() |> Application.get_env(:ash_domains, [])
  end

  defp domains(_config), do: []
end
