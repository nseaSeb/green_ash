defmodule GreenAsh.Registry do
  @moduledoc """
  Découverte, au runtime, des resources / actions Ash à partir de la liste de
  domaines fournie par l'hôte (via la macro de routeur), et résolution
  module <-> slug / clé primaire pour les routes de la console.

  Aucune resource n'est référencée en dur : tout vient des domaines passés en
  argument et de l'introspection Ash.
  """

  @doc "Toutes les resources exposées par `domains`."
  def resources(domains) do
    domains
    |> Enum.flat_map(&Ash.Domain.Info.resources/1)
    |> Enum.uniq()
  end

  @doc "Actions d'une resource."
  def actions(resource), do: Ash.Resource.Info.actions(resource)

  @doc "Libellé court d'une resource (dernier segment du module)."
  def resource_label(resource), do: resource |> Module.split() |> List.last()

  @doc "Description humaine d'une resource, si définie, sinon son libellé."
  def resource_title(resource) do
    Ash.Resource.Info.description(resource) || resource_label(resource)
  end

  @doc "Slug URL d'une resource (ex: MyApp.Bank.Account -> \"account\")."
  def resource_slug(resource), do: resource |> resource_label() |> Macro.underscore()

  @doc "Resource correspondant à un slug parmi `domains`, ou nil."
  def resource_by_slug(domains, slug),
    do: Enum.find(resources(domains), &(resource_slug(&1) == slug))

  @doc "Struct d'action par nom (string ou atom)."
  def action(resource, name) when is_binary(name),
    do: action(resource, String.to_existing_atom(name))

  def action(resource, name) when is_atom(name),
    do: Ash.Resource.Info.action(resource, name)

  @doc "Libellé d'une action : sa description si définie, sinon son nom humanisé."
  def action_label(action) do
    action.description || Phoenix.Naming.humanize(action.name)
  end

  @doc """
  Encode la clé primaire d'un enregistrement en un token pour URL/formulaire.

  PK simple -> la valeur brute (rétrocompatible). PK composite -> un token
  base64url d'un JSON `{champ => valeur}`.
  """
  def encode_pk(%resource{} = record) do
    case Ash.Resource.Info.primary_key(resource) do
      [single] ->
        to_string(Map.get(record, single))

      fields ->
        fields
        |> Map.new(fn f -> {to_string(f), to_string(Map.get(record, f))} end)
        |> Jason.encode!()
        |> Base.url_encode64(padding: false)
    end
  end

  @doc "Décode un token de clé primaire en identifiant utilisable par `Ash.get/2`."
  def decode_pk(resource, token) do
    case Ash.Resource.Info.primary_key(resource) do
      [_single] ->
        {:ok, token}

      fields ->
        with {:ok, bin} <- Base.url_decode64(token, padding: false),
             {:ok, map} <- Jason.decode(bin) do
          {:ok, Map.new(fields, fn f -> {f, map[to_string(f)]} end)}
        else
          _ -> :error
        end
    end
  end
end
