defmodule GreenAsh.Registry do
  @moduledoc """
  Runtime discovery of Ash resources / actions from the list of domains
  provided by the host (via the router macro), and module <-> slug / primary
  key resolution for the console's routes.

  No resource is hardcoded: everything comes from the domains passed as an
  argument and from Ash introspection.
  """

  @doc "All resources exposed by `domains`."
  def resources(domains) do
    domains
    |> Enum.flat_map(&Ash.Domain.Info.resources/1)
    |> Enum.uniq()
  end

  @doc "Actions of a resource."
  def actions(resource), do: Ash.Resource.Info.actions(resource)

  @doc "Short label of a resource (last segment of the module)."
  def resource_label(resource), do: resource |> Module.split() |> List.last()

  @doc "Human description of a resource, if defined, otherwise its label."
  def resource_title(resource) do
    Ash.Resource.Info.description(resource) || resource_label(resource)
  end

  @doc "URL slug of a resource (e.g.: MyApp.Bank.Account -> \"account\")."
  def resource_slug(resource), do: resource |> resource_label() |> Macro.underscore()

  @doc "Resource matching a slug among `domains`, or nil."
  def resource_by_slug(domains, slug),
    do: Enum.find(resources(domains), &(resource_slug(&1) == slug))

  @doc "Action struct by name (string or atom)."
  def action(resource, name) when is_binary(name),
    do: action(resource, String.to_existing_atom(name))

  def action(resource, name) when is_atom(name),
    do: Ash.Resource.Info.action(resource, name)

  @doc "Label of an action: its description if defined, otherwise its humanized name."
  def action_label(action) do
    action.description || Phoenix.Naming.humanize(action.name)
  end

  @doc """
  Encodes a record's primary key into a token for URL/form use.

  Simple PK -> the raw value (backward-compatible). Composite PK -> a
  base64url token of a JSON `{field => value}`.
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

  @doc "Decodes a primary key token into an identifier usable by `Ash.get/2`."
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
