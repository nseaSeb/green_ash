defmodule GreenAsh.Actor do
  @moduledoc """
  Gestion de l'« acteur » de la console : l'enregistrement Ash au nom duquel les
  actions sont exécutées (pour éprouver les policies). Stocké en session HTTP
  (une LiveView ne peut pas écrire la session via le socket : cf.
  `GreenAsh.ActorController`) et rethreadé dans tous les appels Ash.
  """
  alias GreenAsh.Registry

  @session_key "green_ash_actor"

  def session_key, do: @session_key

  @doc "Résout l'acteur depuis la session (parmi `domains`), ou nil."
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

  @doc "Libellé court de l'acteur pour l'en-tête (ex. \"Account:1b78…\")."
  def label(nil), do: "anonyme"

  def label(%resource{} = record) do
    pk = resource |> Ash.Resource.Info.primary_key() |> List.first()
    id = record |> Map.get(pk) |> to_string() |> String.slice(0, 8)
    "#{Registry.resource_label(resource)}:#{id}"
  end
end
