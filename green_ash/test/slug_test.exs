defmodule GreenAsh.SlugTest do
  @moduledoc """
  Slugs must name exactly one resource.

  Two resources ending in the same module segment — `Bank.Account` and
  `Sales.Account`, an ordinary shape once an app has more than one domain —
  both slugged to "account". `resource_by_slug/2` answered the first for both,
  so the second was unreachable and every link to it, every `:list` and every
  `:actor` naming it, quietly resolved to the other resource. The console
  showed one thing while claiming to show another, with nothing on screen to
  suggest it.
  """
  use ExUnit.Case, async: true

  alias GreenAsh.{Command, Registry}
  alias GreenAsh.TestSupport.Twin

  @twins [Twin.Bank, Twin.Sales]

  describe "when nothing collides" do
    test "the short slug is kept, so existing URLs do not move" do
      alias GreenAsh.TestSupport.{Account, Bank}

      assert Registry.resource_slug(Account, [Bank]) == "account"
      assert Registry.resource_by_slug([Bank], "account") == Account
    end

    test "a single twin domain on its own still gets the short slug" do
      assert Registry.resource_slug(Twin.Bank.Account, [Twin.Bank]) == "account"
    end
  end

  describe "when two resources share a last segment" do
    test "neither keeps the short slug — the choice is symmetric" do
      bank = Registry.resource_slug(Twin.Bank.Account, @twins)
      sales = Registry.resource_slug(Twin.Sales.Account, @twins)

      refute bank == "account"
      refute sales == "account"
      refute bank == sales
    end

    test "the slugs are qualified by the domain segment" do
      assert Registry.resource_slug(Twin.Bank.Account, @twins) == "bank_account"
      assert Registry.resource_slug(Twin.Sales.Account, @twins) == "sales_account"
    end

    test "each slug resolves back to its own resource, both ways" do
      for resource <- [Twin.Bank.Account, Twin.Sales.Account] do
        slug = Registry.resource_slug(resource, @twins)
        assert Registry.resource_by_slug(@twins, slug) == resource
      end
    end

    test "the ambiguous slug now resolves to nothing rather than to the wrong one" do
      # Silence is the point: answering "account" with either resource is the
      # bug. A nil sends the console back to the menu.
      assert Registry.resource_by_slug(@twins, "account") == nil
    end

    test ":list builds a path that leads to the resource it names" do
      assert {:navigate, path} = Command.parse(":list sales_account", "/cli", @twins)
      assert path == "/cli/r/sales_account/list/read"

      # The round trip is what matters: the path the command builds must be
      # the path the route resolves.
      ["", "cli", "r", slug, "list", _] = String.split(path, "/")
      assert Registry.resource_by_slug(@twins, slug) == Twin.Sales.Account
    end

    test "the short name is refused rather than silently picking one" do
      assert {:message, message} = Command.parse(":list account", "/cli", @twins)
      assert message =~ "Unknown resource"
    end
  end
end
