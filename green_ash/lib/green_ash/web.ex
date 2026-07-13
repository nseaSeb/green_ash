defmodule GreenAsh.Web do
  @moduledoc """
  Entry point `use GreenAsh.Web, :live_view` for the console's LiveViews.
  Imports nothing from the host application: only Phoenix.LiveView, the
  lib's components, and a path helper relative to the mount base.
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

  @doc "Builds an absolute path from the mount base (e.g. \"/cli\")."
  def ga_path(base, rest), do: base <> rest

  defmacro __using__(which) when is_atom(which), do: apply(__MODULE__, which, [])
end
