defmodule GreenAsh.Tenant do
  @moduledoc """
  The console's current tenant: the value threaded through every Ash call so
  that multitenant resources can be browsed.

  A tenant is application knowledge — Ash can say a resource needs one, never
  which one you mean — so it is asked for rather than inferred. Kept in the
  HTTP session beside the actor, and for the same reason: a LiveView cannot
  write the session through its socket (see `GreenAsh.SessionController`).

  There is no validation of the value. Ash accepts any term as a tenant, and a
  console whose job is to probe your resources has no business deciding which
  tenants are real.
  """

  @session_key "green_ash_tenant"

  def session_key, do: @session_key

  @doc "The tenant stored in the session, or nil."
  def from_session(%{@session_key => tenant}) when is_binary(tenant) and tenant != "", do: tenant
  def from_session(_session), do: nil

  @doc ~S'Short label for the header (e.g. `"tenant:acme"`), or nil when unset.'
  def label(nil), do: nil
  def label(tenant), do: "tenant:" <> to_string(tenant)
end
