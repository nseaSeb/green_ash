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

  @doc "Resolves the actor from the session (among `domains`), or nil."
  def from_session(session, domains) do
    case session do
      %{@session_key => %{"slug" => slug, "id" => id}} ->
        with resource when not is_nil(resource) <- Registry.resource_by_slug(domains, slug),
             {:ok, record} <- Ash.get(resource, id, authorize?: false) do
          record
        else
          _ -> nil
        end

      _ ->
        nil
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
