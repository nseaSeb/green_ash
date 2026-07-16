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
      import GreenAsh.Web, only: [ga_path: 2, assign_tenant_notice: 2]
      alias GreenAsh.{Actor, Command, Field, Registry}
      alias Phoenix.LiveView.JS
    end
  end

  @doc "Builds an absolute path from the mount base (e.g. \"/cli\")."
  def ga_path(base, rest), do: base <> rest

  # Switches a screen over to `Components.tenant_notice/1`: the resource
  # declares a tenant the console cannot set, so no read may be attempted.
  # Shared by Screen and Subfile, which both refuse the same resources for
  # the same reason and must say so identically.
  @doc false
  def assign_tenant_notice(socket, resource) do
    Phoenix.Component.assign(socket,
      tenant_notice: true,
      resource: resource,
      strategy: Ash.Resource.Info.multitenancy_strategy(resource)
    )
  end

  defmacro __using__(which) when is_atom(which), do: apply(__MODULE__, which, [])
end
