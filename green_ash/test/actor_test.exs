defmodule GreenAsh.ActorTest do
  use ExUnit.Case, async: true

  alias GreenAsh.Actor
  alias GreenAsh.TestSupport.{Account, Bank}

  @domains [Bank]

  test "label et résolution depuis la session" do
    assert Actor.label(nil) == "anonyme"

    {:ok, acc} =
      Account
      |> Ash.Changeset.for_create(:open, %{holder: "Chef", initial_deposit: Decimal.new("0")})
      |> Ash.create()

    session = %{Actor.session_key() => %{"slug" => "account", "id" => acc.id}}
    resolved = Actor.from_session(session, @domains)

    assert resolved.id == acc.id
    assert Actor.label(resolved) =~ "Account:"
    assert Actor.from_session(%{}, @domains) == nil
  end
end
