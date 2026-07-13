defmodule GreenAsh.CommandTest do
  use ExUnit.Case, async: true

  alias GreenAsh.Command
  alias GreenAsh.TestSupport.Bank

  @domains [Bank]
  @base "/cli"

  test "navigation built from the mount base" do
    assert Command.parse(":menu", @base, @domains) == {:navigate, "/cli"}

    assert Command.parse(":list account", @base, @domains) ==
             {:navigate, "/cli/r/account/list/read"}

    assert Command.parse(":new account", @base, @domains) == {:navigate, "/cli/r/account/a/open"}
    assert Command.parse(":debug", @base, @domains) == :toggle_debug
    assert Command.parse(":whoami", @base, @domains) == :whoami
  end

  test "actor -> controller redirect with encoded return" do
    assert {:redirect, "/cli/actor?slug=account&id=42&return=%2Fcli"} =
             Command.parse(":actor account 42", @base, @domains)

    assert {:redirect, "/cli/actor?return=%2Fcli"} = Command.parse(":actor none", @base, @domains)
  end

  test "invalid inputs" do
    assert {:message, _} = Command.parse(":list inconnu", @base, @domains)
    assert {:message, _} = Command.parse(":wat", @base, @domains)
    assert Command.parse("3", @base, @domains) == :not_command
    assert Command.parse(":", @base, @domains) == :noop
  end
end
