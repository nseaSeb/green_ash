defmodule GreenAsh.OnMount do
  @moduledoc """
  `on_mount` posé par la macro de routeur : injecte dans chaque LiveView la liste
  de domaines, la base de montage et l'acteur courant (résolu depuis la session).

  Sans `domains:` explicite passé à la macro, la liste est lue **à chaque
  requête** depuis `Application.get_env(otp_app, :ash_domains, [])` — un
  domaine ajouté après coup (via les générateurs Ash, qui maintiennent déjà
  cette config) apparaît donc immédiatement, sans réinstallation.
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
