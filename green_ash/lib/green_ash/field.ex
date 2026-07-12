defmodule GreenAsh.Field do
  @moduledoc """
  Introspection d'une action Ash -> specs de champs -> type de widget HTML.

  À partir d'une resource et d'une action, liste les champs saisissables
  (attributs acceptés + arguments) et décide quel widget rendre pour chaque type
  Ash. Les types non reconnus retombent sur un textarea JSON (avec un log).
  """
  require Logger

  @doc """
  Liste ordonnée des champs saisissables pour `action` sur `resource` :
  d'abord les attributs acceptés, puis les arguments de l'action.
  """
  def specs(resource, action) do
    accepted =
      for name <- accepted_attributes(action) do
        attr = Ash.Resource.Info.attribute(resource, name)
        build_spec(name, :attribute, attr.type, attr.constraints || [], attr.allow_nil?)
      end

    arguments =
      for arg <- Map.get(action, :arguments, []) do
        build_spec(arg.name, :argument, arg.type, arg.constraints || [], arg.allow_nil?)
      end

    accepted ++ arguments
  end

  defp accepted_attributes(action) do
    case Map.get(action, :accept) do
      nil -> []
      list when is_list(list) -> list
    end
  end

  defp build_spec(name, kind, type, constraints, allow_nil?) do
    input_type = input_type(type, constraints)

    %{
      name: name,
      kind: kind,
      type: type,
      constraints: constraints,
      allow_nil?: allow_nil?,
      input_type: input_type,
      options: options(type, constraints),
      label: Phoenix.Naming.humanize(name),
      rest: rest_for(type, input_type)
    }
  end

  @doc "Décide le `type=` du widget HTML pour un type Ash donné."
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
    Logger.debug("[green_ash] type Ash non mappé, fallback textarea JSON: #{inspect(type)}")
    "textarea"
  end

  @doc "Options `{label, value}` pour un widget select, ou nil si non-enum."
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
