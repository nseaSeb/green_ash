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

  @doc """
  Whether `resource` cannot be read without a tenant being set.

  Mirrors the check Ash itself performs before running a read
  (`Ash.Actions.Read.validate_multitenancy/1`): a resource is only
  constrained if it declares a multitenancy strategy *and* is not `global?`.

  The console has no tenant to offer yet, so such a resource is signalled
  rather than opened — without this it reaches `Ash.read!/2` and raises
  `Ash.Error.Invalid.TenantRequired`.
  """
  def tenant_required?(resource) do
    !is_nil(Ash.Resource.Info.multitenancy_strategy(resource)) &&
      !Ash.Resource.Info.multitenancy_global?(resource)
  end

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

  @doc """
  Action struct by name (string or atom), or nil when `resource` declares no
  such action.

  Action names arrive from the URL, so an unknown one is a routine event, not
  a bug: `String.to_existing_atom/1` on a name no atom exists for raises, and
  a raise inside `mount/3` is a 500 rather than a screen saying what is wrong.
  """
  def action(resource, name) when is_binary(name) do
    case existing_atom(name) do
      {:ok, atom} -> action(resource, atom)
      :error -> nil
    end
  end

  def action(resource, name) when is_atom(name),
    do: Ash.Resource.Info.action(resource, name)

  defp existing_atom(name) do
    {:ok, String.to_existing_atom(name)}
  rescue
    ArgumentError -> :error
  end

  @doc """
  Whether `action` declares pagination.

  Matters to the caller because a paginated read returns an `Ash.Page.*`
  struct rather than a list — `length/1` on one raises. Note that Ash's
  `defaults [:read]` declares pagination while a hand-written `read` block
  does not, so this cannot be assumed either way.
  """
  def paginated?(action), do: Map.get(action, :pagination) not in [nil, false]

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
