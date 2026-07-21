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

      import GreenAsh.Web,
        only: [
          ga_path: 2,
          tenant_notice: 1,
          no_action_notice: 2,
          not_readable_notice: 2
        ]

      alias GreenAsh.{Actor, Command, Field, Registry}
      alias Phoenix.LiveView.JS
    end
  end

  @doc "Builds an absolute path from the mount base (e.g. \"/cli\")."
  def ga_path(base, rest), do: base <> rest

  # Descriptions of what the console is refusing to open, assigned as
  # `:notice` and rendered by `Components.notice/1`. Shared by Screen and
  # Subfile, which refuse the same things for the same reasons and must say
  # so identically.
  #
  # Each of these replaces a crash: without them the resource/action reaches
  # Ash and raises inside `mount/3`.
  @doc false
  def tenant_notice(resource) do
    %{
      kind: :tenant,
      resource: resource,
      strategy: Ash.Resource.Info.multitenancy_strategy(resource)
    }
  end

  @doc false
  def no_action_notice(resource, name), do: %{kind: :no_action, resource: resource, name: name}

  @doc false
  def not_readable_notice(resource, action),
    do: %{kind: :not_readable, resource: resource, name: action.name, type: action.type}

  defmacro __using__(which) when is_atom(which), do: apply(__MODULE__, which, [])
end
