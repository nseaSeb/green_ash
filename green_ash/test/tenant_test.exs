defmodule GreenAsh.TenantTest do
  @moduledoc """
  Picking a tenant, and what follows from it.

  0.2.0 stopped multitenant resources crashing the console by refusing to open
  them: Ash can say a resource needs a tenant, never which one you mean. Asking
  is the missing half. The refusal stays for as long as no tenant is set — the
  screens are the same, the answer just changes.

  The tests that matter most here are the ones checking the tenant is actually
  *applied* rather than merely stored: a console that displayed "tenant:acme"
  while listing everyone's rows would be worse than one that refused outright.
  """
  use ExUnit.Case, async: true

  require Ash.Query

  alias GreenAsh.{Command, Tenant}
  alias GreenAsh.Live.{Menu, Screen, Subfile}
  alias GreenAsh.TestSupport.{Doc, Org, Project, Saas}

  @domains [Saas]
  @base "/cli"

  defp socket(assigns \\ %{}) do
    %Phoenix.LiveView.Socket{
      assigns:
        Map.merge(
          %{
            __changed__: %{},
            domains: @domains,
            base: @base,
            tenant: nil,
            actor: nil,
            actor_notice: nil
          },
          assigns
        )
    }
  end

  defp mount_list(slug, action, assigns) do
    {:ok, socket} = Subfile.mount(%{"resource" => slug, "action" => action}, %{}, socket(assigns))

    case socket.assigns do
      %{notice: _} -> socket
      _ -> elem(Subfile.handle_params(%{}, @base, socket), 1)
    end
  end

  describe "the session" do
    test "a tenant is read back from the session, and its absence is nil" do
      assert Tenant.from_session(%{Tenant.session_key() => "acme"}) == "acme"
      assert Tenant.from_session(%{}) == nil
      # An empty string is how a cleared form field arrives; it is not a tenant.
      assert Tenant.from_session(%{Tenant.session_key() => ""}) == nil
    end

    test "OnMount hands the tenant to every screen" do
      session = %{
        "green_ash" => %{"domains" => ["Elixir.GreenAsh.TestSupport.Saas"], "base" => @base},
        Tenant.session_key() => "acme"
      }

      {:cont, socket} =
        GreenAsh.OnMount.on_mount(:default, %{}, session, %Phoenix.LiveView.Socket{
          assigns: %{__changed__: %{}}
        })

      assert socket.assigns.tenant == "acme"
    end
  end

  describe "the command" do
    test ":tenant <value> goes through the controller, like :actor does" do
      assert {:redirect, "/cli/tenant?value=acme&return=%2Fcli"} =
               Command.parse(":tenant acme", @base, @domains)
    end

    test ":tenant none clears it" do
      assert Command.parse(":tenant none", @base, @domains) ==
               {:redirect, "/cli/tenant?return=%2Fcli"}
    end

    test "bare :tenant reports rather than clearing" do
      # Clearing is destructive — every multitenant screen closes behind it —
      # and `:cols` alone already means "tell me". The same keystroke must not
      # mean "undo" here, or checking which tenant you are in loses it.
      assert Command.parse(":tenant", @base, @domains) == :whoami

      {:noreply, socket} = Command.apply_to(socket(%{tenant: "acme", message: ""}), ":tenant")
      assert socket.assigns.message =~ "tenant:acme"
    end

    test "a value needing encoding survives the trip" do
      # Tenants are often schema names or ids; nothing says they are URL-safe.
      assert {:redirect, path} = Command.parse(":tenant acme&corp/1", @base, @domains)

      assert path =~ "value=acme%26corp%2F1"

      assert %{"value" => "acme&corp/1"} =
               path |> URI.parse() |> Map.get(:query) |> URI.decode_query()
    end

    test "two words are refused rather than guessed at" do
      # The command line splits on spaces, so "acme corp" is as likely a typo
      # as a tenant. Saying so beats silently picking one of the halves.
      assert {:message, message} = Command.parse(":tenant acme corp", @base, @domains)
      assert message =~ "Usage"
    end

    test ":whoami reports the tenant alongside the actor" do
      {:noreply, socket} =
        Command.apply_to(socket(%{tenant: "acme", message: ""}), ":whoami")

      assert socket.assigns.message =~ "anonymous"
      assert socket.assigns.message =~ "tenant:acme"
    end

    test ":whoami says nothing about a tenant when there is none" do
      {:noreply, socket} = Command.apply_to(socket(%{message: ""}), ":whoami")

      refute socket.assigns.message =~ "tenant"
    end
  end

  describe "without a tenant, the refusal stands" do
    test "the list still refuses" do
      assert mount_list("project", "read", %{}).assigns.notice.kind == :tenant
    end

    test "the menu still flags the resource" do
      {:ok, menu} = Menu.mount(%{}, %{}, socket(%{}))

      assert "Project · tenant required" in Enum.map(menu.assigns.options, & &1.detail)
    end

    test "the refusal now points at the way out" do
      socket = mount_list("project", "read", %{})

      html =
        socket.assigns
        |> Map.put(:__changed__, nil)
        |> Subfile.render()
        |> Phoenix.HTML.Safe.to_iodata()
        |> IO.iodata_to_binary()

      assert html =~ ":tenant"
    end
  end

  describe "with a tenant, the resource opens" do
    setup do
      Ash.create!(Project, %{org_id: "acme", name: "Apollo"}, tenant: "acme")
      Ash.create!(Project, %{org_id: "acme", name: "Gemini"}, tenant: "acme")
      Ash.create!(Project, %{org_id: "initech", name: "TPS"}, tenant: "initech")
      :ok
    end

    test "the list opens instead of refusing" do
      socket = mount_list("project", "read", %{tenant: "acme"})

      refute Map.has_key?(socket.assigns, :notice)
    end

    test "and shows only that tenant's rows" do
      # The point of the whole feature: stored is not the same as applied.
      socket = mount_list("project", "read", %{tenant: "acme"})

      assert socket.assigns.rows |> Enum.map(& &1.name) |> Enum.sort() == ["Apollo", "Gemini"]
    end

    test "another tenant sees its own, and only its own" do
      socket = mount_list("project", "read", %{tenant: "initech"})

      assert Enum.map(socket.assigns.rows, & &1.name) == ["TPS"]
    end

    test "a tenant with nothing in it shows an empty list, not someone else's" do
      socket = mount_list("project", "read", %{tenant: "nobody"})

      assert socket.assigns.rows == []
      assert socket.assigns.read_error == nil
    end

    test "the action screen opens too" do
      {:ok, socket} =
        Screen.mount(
          %{"resource" => "project", "action" => "create"},
          %{},
          socket(%{tenant: "acme"})
        )

      refute Map.has_key?(socket.assigns, :notice)
      assert socket.assigns.action.name == :create
    end

    test "a create through the screen lands in the current tenant" do
      {:ok, socket} =
        Screen.mount(
          %{"resource" => "project", "action" => "create"},
          %{},
          socket(%{tenant: "initech"})
        )

      {:noreply, _socket} =
        Screen.handle_event(
          "submit",
          %{"form" => %{"name" => "Initrode", "org_id" => "initech"}},
          socket
        )

      assert [%{name: "Initrode"}] =
               Project
               |> Ash.Query.filter(name == "Initrode")
               |> Ash.read!(tenant: "initech")
    end

    test "the menu stops flagging the resource" do
      {:ok, menu} = Menu.mount(%{}, %{}, socket(%{tenant: "acme"}))

      details = Enum.map(menu.assigns.options, & &1.detail)
      assert "Project" in details
      refute "Project · tenant required" in details
    end

    test "the header says which tenant, on every screen" do
      html =
        mount_list("project", "read", %{tenant: "acme"}).assigns
        |> Map.put(:__changed__, nil)
        |> Subfile.render()
        |> Phoenix.HTML.Safe.to_iodata()
        |> IO.iodata_to_binary()

      # A list scoped to the wrong tenant and an empty one look identical
      # without this.
      assert html =~ "tenant:acme"
    end

    test "the other multitenancy strategy behaves the same" do
      # :attribute scopes by a column, :context hands the tenant to the data
      # layer. The console passes `tenant:` either way and never inspects the
      # strategy — asserted rather than assumed.
      Ash.create!(Doc, %{title: "Charter"}, tenant: "acme")
      Ash.create!(Doc, %{title: "Invoice"}, tenant: "initech")

      assert Enum.map(mount_list("doc", "read", %{tenant: "acme"}).assigns.rows, & &1.title) ==
               ["Charter"]

      assert mount_list("doc", "read", %{}).assigns.notice.kind == :tenant
    end

    test "a resource that never needed a tenant is unaffected by one being set" do
      Ash.create!(Org, %{slug: "acme"})

      socket = mount_list("org", "read", %{tenant: "acme"})

      assert length(socket.assigns.rows) == 1
    end
  end

  describe "the actor follows the tenant" do
    test "a tenant-scoped actor loads once a tenant is set" do
      project = Ash.create!(Project, %{org_id: "acme", name: "Apollo"}, tenant: "acme")
      session = %{GreenAsh.Actor.session_key() => %{"slug" => "project", "id" => project.id}}

      assert {:ok, loaded} = GreenAsh.Actor.resolve(session, @domains, "acme")
      assert loaded.id == project.id
    end

    test "without a tenant it is still refused, and now says how to fix it" do
      session = %{GreenAsh.Actor.session_key() => %{"slug" => "project", "id" => "whatever"}}

      assert {:error, message} = GreenAsh.Actor.resolve(session, @domains, nil)
      assert message =~ ":tenant <value>"
    end
  end
end
