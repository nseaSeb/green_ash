defmodule GreenAsh.OnMount do
  @moduledoc """
  `on_mount` set by the router macro: injects into each LiveView the list of
  domains, the mount base, and the current actor (resolved from the session).

  When an actor is stored in the session but cannot be loaded, `actor` is nil
  and `actor_notice` carries the reason for the screen to display — see
  `GreenAsh.Actor.resolve/2`.

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

    {actor, notice} =
      case GreenAsh.Actor.resolve(session, domains) do
        {:ok, record} -> {record, nil}
        :none -> {nil, nil}
        {:error, message} -> {nil, message}
      end

    {:cont,
     assign(socket,
       domains: domains,
       base: base,
       actor: actor,
       actor_notice: notice
     )}
  end

  defp domains(%{"domains" => list}) when is_list(list),
    do: Enum.map(list, &String.to_existing_atom/1)

  defp domains(%{"otp_app" => otp_app}) when is_binary(otp_app) do
    otp_app |> String.to_existing_atom() |> Application.get_env(:ash_domains, [])
  end

  defp domains(_config), do: []
end
