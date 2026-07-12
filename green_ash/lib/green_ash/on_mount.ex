defmodule GreenAsh.OnMount do
  @moduledoc """
  `on_mount` posé par la macro de routeur : injecte dans chaque LiveView la liste
  de domaines, la base de montage et l'acteur courant (résolu depuis la session).
  """
  import Phoenix.Component, only: [assign: 2]

  def on_mount(:default, _params, session, socket) do
    config = session["green_ash"] || %{}
    domains = config |> Map.get("domains", []) |> Enum.map(&String.to_existing_atom/1)
    base = Map.get(config, "base", "/")

    {:cont,
     assign(socket,
       domains: domains,
       base: base,
       actor: GreenAsh.Actor.from_session(session, domains)
     )}
  end
end
