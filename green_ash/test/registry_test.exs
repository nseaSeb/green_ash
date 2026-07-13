defmodule GreenAsh.RegistryTest do
  use ExUnit.Case, async: true

  alias GreenAsh.Registry
  alias GreenAsh.TestSupport.{Account, Bank}

  @domains [Bank]

  test "resource discovery and resolution by slug" do
    assert Account in Registry.resources(@domains)
    assert Registry.resource_slug(Account) == "account"
    assert Registry.resource_by_slug(@domains, "account") == Account
    assert Registry.resource_by_slug(@domains, "unknown") == nil
  end

  test "encode_pk/decode_pk round-trip (simple PK)" do
    {:ok, acc} =
      Account
      |> Ash.Changeset.for_create(:open, %{holder: "A", initial_deposit: Decimal.new("1")})
      |> Ash.create()

    token = Registry.encode_pk(acc)
    assert token == to_string(acc.id)
    assert Registry.decode_pk(Account, token) == {:ok, token}
  end
end
