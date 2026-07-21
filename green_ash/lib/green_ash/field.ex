defmodule GreenAsh.Field do
  @moduledoc """
  Introspection of an Ash action -> field specs -> HTML widget type.

  From a resource and an action, lists the fillable fields (accepted
  attributes + arguments) and decides which widget to render for each Ash
  type. Unrecognized types fall back to a JSON textarea (with a log).

  `specs/2` is pure introspection and touches no data. Relationship fields
  need the related records to offer a choice, so that read is a separate
  step — `with_options/2`.
  """
  require Logger

  alias GreenAsh.Registry

  # Beyond this many related records the field stays a plain id box. A select
  # of ten thousand rows helps nobody, and the read is not free.
  @max_options 100

  @doc """
  Ordered list of fillable fields for `action` on `resource`: first the
  accepted attributes, then the action's arguments.
  """
  def specs(resource, action) do
    accepted =
      for name <- accepted_attributes(action) do
        attr = Ash.Resource.Info.attribute(resource, name)

        build_spec(name, :attribute, attr.type, attr.constraints || [], attr.allow_nil?,
          relationship: belongs_to(resource, name)
        )
      end

    arguments =
      for arg <- Map.get(action, :arguments, []) do
        build_spec(arg.name, :argument, arg.type, arg.constraints || [], arg.allow_nil?)
      end

    accepted ++ arguments
  end

  # Only accepted attributes are matched: an argument that happens to hold a
  # foreign key is not declared as one, so there is nothing to introspect.
  defp belongs_to(resource, name) do
    Enum.find(Ash.Resource.Info.relationships(resource), fn relationship ->
      relationship.type == :belongs_to and relationship.source_attribute == name
    end)
  end

  @doc """
  Fills in the choices of relationship fields by reading the related records.

  Separate from `specs/2` because it reads: introspection can say a field
  points at another resource, but not what is in it. Needs the actor, so the
  choice is the one that actor is allowed to see.

  A field is left exactly as `specs/2` built it — a plain id box — whenever a
  choice cannot honestly be offered: more than #{@max_options} records, a
  resource needing a tenant the console cannot set, or a read the actor may
  not perform. Better a box you can paste an id into than an empty select
  that looks like the table is empty.
  """
  def with_options(specs, actor) do
    Enum.map(specs, fn
      %{relationship: relationship} = spec when not is_nil(relationship) ->
        load_options(spec, relationship, actor)

      spec ->
        spec
    end)
  end

  defp load_options(spec, relationship, actor) do
    case read_related(relationship.destination, actor) do
      {:ok, records} ->
        %{spec | input_type: "select", options: Enum.map(records, &option/1)}

      :error ->
        spec
    end
  end

  defp read_related(destination, actor) do
    if Registry.tenant_required?(destination) do
      :error
    else
      destination
      |> Ash.Query.limit(@max_options + 1)
      |> Ash.read(actor: actor)
      |> case do
        {:ok, records} when length(records) <= @max_options -> {:ok, records}
        _too_many_or_refused -> :error
      end
    end
  end

  # "Alice Martin · 8f3a2c71" — a name to recognise, and enough of the id to
  # tell two of the same name apart.
  defp option(%resource{} = record) do
    key = resource |> Ash.Resource.Info.primary_key() |> List.first()
    id = record |> Map.get(key) |> to_string()

    label =
      case display_attribute(resource, key) do
        nil -> id
        field -> "#{Map.get(record, field)} · #{String.slice(id, 0, 8)}"
      end

    {label, id}
  end

  defp display_attribute(resource, key) do
    resource
    |> Ash.Resource.Info.public_attributes()
    |> Enum.find(fn attr ->
      attr.name != key and attr.type in [Ash.Type.String, Ash.Type.CiString]
    end)
    |> case do
      nil -> nil
      attr -> attr.name
    end
  end

  defp accepted_attributes(action) do
    case Map.get(action, :accept) do
      nil -> []
      list when is_list(list) -> list
    end
  end

  defp build_spec(name, kind, type, constraints, allow_nil?, opts \\ []) do
    input_type = input_type(type, constraints)

    %{
      name: name,
      kind: kind,
      type: type,
      constraints: constraints,
      allow_nil?: allow_nil?,
      input_type: input_type,
      options: options(type, constraints),
      relationship: Keyword.get(opts, :relationship),
      label: Phoenix.Naming.humanize(name),
      rest: rest_for(type, input_type)
    }
  end

  @doc "Decides the HTML widget's `type=` for a given Ash type."
  def input_type(type, constraints) do
    cond do
      enum_values(type, constraints) != nil ->
        "select"

      type in [Ash.Type.String, Ash.Type.CiString, Ash.Type.UUID, Ash.Type.UUIDv7] ->
        "text"

      type == Ash.Type.Integer ->
        "number"

      type in [Ash.Type.Decimal, Ash.Type.Float] ->
        "number"

      type == Ash.Type.Boolean ->
        "checkbox"

      type == Ash.Type.Date ->
        "date"

      type in [Ash.Type.UtcDatetime, Ash.Type.UtcDatetimeUsec, Ash.Type.NaiveDatetime] ->
        "datetime-local"

      true ->
        fallback(type)
    end
  end

  defp fallback(type) do
    Logger.debug(
      "[green_ash] Ash type not mapped, falling back to JSON textarea: #{inspect(type)}"
    )

    "textarea"
  end

  @doc "Options `{label, value}` for a select widget, or nil if not an enum."
  def options(type, constraints) do
    case enum_values(type, constraints) do
      nil -> nil
      values -> Enum.map(values, &{Phoenix.Naming.humanize(&1), to_string(&1)})
    end
  end

  defp enum_values(type, constraints) do
    cond do
      is_list(constraints[:one_of]) -> constraints[:one_of]
      is_atom(type) and function_exported?(type, :values, 0) -> type.values()
      true -> nil
    end
  end

  defp rest_for(type, "number") when type in [Ash.Type.Decimal, Ash.Type.Float],
    do: [step: "any"]

  defp rest_for(_type, _input_type), do: []
end
