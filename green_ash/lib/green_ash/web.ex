defmodule GreenAsh.Web do
  @moduledoc """
  Point d'entrée `use GreenAsh.Web, :live_view` pour les LiveViews de la console.
  N'importe rien de l'application hôte : uniquement Phoenix.LiveView, les
  composants de la lib et un helper de chemin relatif à la base de montage.
  """

  def live_view do
    quote do
      use Phoenix.LiveView

      import GreenAsh.Components
      import GreenAsh.Web, only: [ga_path: 2]
      alias GreenAsh.{Actor, Command, Field, Registry}
      alias Phoenix.LiveView.JS
    end
  end

  @doc "Construit un chemin absolu à partir de la base de montage (ex. \"/cli\")."
  def ga_path(base, rest), do: base <> rest

  defmacro __using__(which) when is_atom(which), do: apply(__MODULE__, which, [])
end
