defmodule GreenAsh.FieldTest do
  use ExUnit.Case, async: true

  alias GreenAsh.Field
  alias GreenAsh.TestSupport.Account

  test "specs déduites de l'action open" do
    action = Ash.Resource.Info.action(Account, :open)
    specs = Field.specs(Account, action)

    by = Map.new(specs, &{&1.name, &1.input_type})
    assert by[:holder] == "text"
    assert by[:opened_on] == "date"
    assert by[:initial_deposit] == "number"
  end

  test "mapping type Ash -> widget, avec fallback" do
    assert Field.input_type(Ash.Type.String, []) == "text"
    assert Field.input_type(Ash.Type.Integer, []) == "number"
    assert Field.input_type(Ash.Type.Boolean, []) == "checkbox"
    assert Field.input_type(Ash.Type.Date, []) == "date"
    assert Field.input_type(Ash.Type.Atom, one_of: [:a, :b]) == "select"
    assert Field.input_type(Ash.Type.Map, []) == "textarea"
  end

  test "UUID/UUIDv7 (clés étrangères de belongs_to) se rendent en texte, pas en fallback" do
    assert Field.input_type(Ash.Type.UUID, []) == "text"
    assert Field.input_type(Ash.Type.UUIDv7, []) == "text"
  end
end
