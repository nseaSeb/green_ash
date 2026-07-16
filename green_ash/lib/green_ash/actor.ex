defmodule GreenAsh.Actor do
  @moduledoc """
  Management of the console's "actor": the Ash record on whose behalf actions
  are executed (to exercise the policies). Stored in the HTTP session (a
  LiveView cannot write the session via the socket: see
  `GreenAsh.ActorController`) and re-threaded through all Ash calls.
  """
  alias GreenAsh.Registry

  @session_key "green_ash_actor"

  def session_key, do: @session_key

  @doc """
  Resolves the actor stored in the session.

  Returns `:none` when no actor is set, `{:ok, record}` when it loads, and
  `{:error, message}` when an actor **is** stored but cannot be loaded.

  The distinction matters: falling back to no actor without a word makes the
  console look like it ran as nobody on purpose. Every policy result then
  reads as a verdict on the policy when it is really a verdict on an actor
  that was never loaded. Callers are expected to surface `message`.
  """
  def resolve(session, domains) do
    case session do
      %{@session_key => %{"slug" => slug, "id" => id}} -> load(domains, slug, id)
      _ -> :none
    end
  end

  defp load(domains, slug, id) do
    case Registry.resource_by_slug(domains, slug) do
      nil ->
        {:error, "Actor dropped: no resource \"#{slug}\" among the exposed domains."}

      resource ->
        # Asking Registry rather than parsing the error Ash would raise: the
        # predicate is the same one the console's screens guard on, and it
        # does not depend on Ash's error shape.
        if Registry.tenant_required?(resource) do
          {:error, "Actor dropped: #{slug} requires a tenant, which the console cannot set."}
        else
          fetch(resource, slug, id)
        end
    end
  end

  defp fetch(resource, slug, id) do
    case Ash.get(resource, id, authorize?: false) do
      {:ok, record} -> {:ok, record}
      {:error, _} -> {:error, "Actor dropped: no #{slug} found with id #{id}."}
    end
  end

  @doc """
  Resolves the actor from the session (among `domains`), or nil.

  Discards the reason a stored actor failed to load; prefer `resolve/2`,
  which reports it.
  """
  def from_session(session, domains) do
    case resolve(session, domains) do
      {:ok, record} -> record
      _ -> nil
    end
  end

  @doc "Short label of the actor for the header (e.g. \"Account:1b78…\")."
  def label(nil), do: "anonymous"

  def label(%resource{} = record) do
    pk = resource |> Ash.Resource.Info.primary_key() |> List.first()
    id = record |> Map.get(pk) |> to_string() |> String.slice(0, 8)
    "#{Registry.resource_label(resource)}:#{id}"
  end
end
