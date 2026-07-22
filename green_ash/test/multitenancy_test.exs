defmodule GreenAsh.MultitenancyTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias GreenAsh.Registry
  alias GreenAsh.TestSupport.{Account, Org, Plan, Project, Saas}

  @domains [Saas]

  defp socket(assigns) do
    %Phoenix.LiveView.Socket{
      assigns:
        Map.merge(
          %{
            __changed__: %{},
            domains: @domains,
            base: "/cli",
            tenant: nil,
            actor: nil,
            actor_notice: nil
          },
          assigns
        )
    }
  end

  defp session(actor) do
    %{"green_ash" => %{"domains" => ["Elixir.GreenAsh.TestSupport.Saas"], "base" => "/cli"}}
    |> Map.merge(if actor, do: %{GreenAsh.Actor.session_key() => actor}, else: %{})
  end

  # Filter/sort/page come from the URL, so a list screen is only settled once
  # handle_params has run — as LiveView does right after mount.
  defp mount_list(slug, action) do
    {:ok, socket} =
      GreenAsh.Live.Subfile.mount(%{"resource" => slug, "action" => action}, %{}, socket(%{}))

    {:noreply, socket} = GreenAsh.Live.Subfile.handle_params(%{}, "/cli", socket)
    {:ok, socket}
  end

  defp on_mount(session) do
    GreenAsh.OnMount.on_mount(:default, %{}, session, %Phoenix.LiveView.Socket{
      assigns: %{__changed__: %{}}
    })
  end

  # Renders a LiveView's own render/1 clause. __changed__: nil forces a full
  # render; %{} would report "nothing changed" and emit an empty diff.
  defp render_view(module, assigns) do
    assigns
    |> Map.put(:__changed__, nil)
    |> module.render()
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  describe "detection" do
    test "tenant_required? mirrors Ash's own validate_multitenancy rule" do
      # :attribute strategy, not global? -> Ash refuses an untenanted read.
      assert Registry.tenant_required?(Project)
      # No multitenancy declared at all.
      refute Registry.tenant_required?(Account)
      refute Registry.tenant_required?(Org)
      # Multitenant but global?: Ash allows the read, so we must not block it.
      refute Registry.tenant_required?(Plan)
    end

    test "the global? exemption is Ash's, not ours: an untenanted read really works" do
      Ash.create!(Plan, %{org_id: "acme", name: "Pro"})

      assert [%Plan{name: "Pro"}] =
               Plan |> Ash.Query.for_read(:read, %{}, actor: nil) |> Ash.read!(actor: nil)
    end

    test "a global? resource mounts normally, unflagged" do
      assert {:ok, mounted} =
               GreenAsh.Live.Subfile.mount(
                 %{"resource" => "plan", "action" => "read"},
                 %{},
                 socket(%{})
               )

      refute Map.has_key?(mounted.assigns, :notice)
    end
  end

  describe "why the guard exists" do
    test "Subfile's read path raises TenantRequired without a tenant" do
      assert_raise Ash.Error.Invalid, ~r/require a tenant to be specified/, fn ->
        Project
        |> Ash.Query.for_read(:read, %{}, actor: nil)
        |> Ash.Query.limit(21)
        |> Ash.read!(actor: nil)
      end
    end

    test "the same read succeeds once a tenant is set" do
      Ash.create!(Project, %{org_id: "acme", name: "Apollo"}, tenant: "acme")

      rows =
        Project
        |> Ash.Query.for_read(:read, %{}, actor: nil)
        |> Ash.Query.set_tenant("acme")
        |> Ash.read!(actor: nil)

      assert [%Project{name: "Apollo"}] = rows
    end
  end

  describe "the console degrades instead of crashing" do
    test "Subfile.mount/3 returns a notice rather than raising" do
      assert {:ok, mounted} =
               GreenAsh.Live.Subfile.mount(
                 %{"resource" => "project", "action" => "read"},
                 %{},
                 socket(%{})
               )

      assert mounted.assigns.notice.kind == :tenant
      assert mounted.assigns.notice.strategy == :attribute
      assert mounted.assigns.notice.resource == Project
    end

    test "Screen.mount/3 returns a notice rather than raising" do
      assert {:ok, mounted} =
               GreenAsh.Live.Screen.mount(
                 %{"resource" => "project", "action" => "create"},
                 %{},
                 socket(%{})
               )

      assert mounted.assigns.notice.kind == :tenant
      # Escape goes back to the menu, not to the list: the list is just as unopenable.
      assert mounted.assigns.return_to == "/cli"
    end

    test "a non-tenant resource still mounts normally" do
      assert {:ok, mounted} = mount_list("org", "read")

      refute Map.has_key?(mounted.assigns, :notice)
      assert mounted.assigns.rows == []
    end

    test "the notice component renders" do
      html =
        render_component(&GreenAsh.Components.notice/1,
          notice: %{kind: :tenant, resource: Project, strategy: :attribute}
        )

      assert html =~ "TENANT REQUIRED"
      assert html =~ "GreenAsh.TestSupport.Project"
      assert html =~ ":attribute"
    end

    test "it offers no advice that would weaken tenant isolation" do
      html =
        render_component(&GreenAsh.Components.notice/1,
          notice: %{kind: :tenant, resource: Project, strategy: :attribute}
        )

      # A debug console must not tell anyone to make a tenant-scoped resource
      # global? to read it: that disables tenant enforcement app-wide. The way
      # out it does offer is the one that keeps isolation intact.
      refute html =~ "global? true"
      assert html =~ ":tenant"
    end

    test "Subfile's own render clause reaches the notice, not just its assigns" do
      {:ok, mounted} =
        GreenAsh.Live.Subfile.mount(
          %{"resource" => "project", "action" => "read"},
          %{},
          socket(%{})
        )

      assert render_view(GreenAsh.Live.Subfile, mounted.assigns) =~ "TENANT REQUIRED"
    end

    test "Screen's own render clause reaches the notice, not just its assigns" do
      {:ok, mounted} =
        GreenAsh.Live.Screen.mount(
          %{"resource" => "project", "action" => "create"},
          %{},
          socket(%{})
        )

      assert render_view(GreenAsh.Live.Screen, mounted.assigns) =~ "TENANT REQUIRED"
    end

    test "Escape from Subfile's notice returns to the menu" do
      {:ok, mounted} =
        GreenAsh.Live.Subfile.mount(
          %{"resource" => "project", "action" => "read"},
          %{},
          socket(%{})
        )

      assert {:noreply, socket} =
               GreenAsh.Live.Subfile.handle_event("keydown", %{"key" => "Escape"}, mounted)

      assert {:live, :redirect, %{to: "/cli"}} = socket.redirected
    end

    test "Escape from Screen's notice returns to the menu, not to the unopenable list" do
      # Guards return_to: the notice path is the only one that assigns it
      # here, and this handler reads it unconditionally.
      {:ok, mounted} =
        GreenAsh.Live.Screen.mount(
          %{"resource" => "project", "action" => "create"},
          %{},
          socket(%{})
        )

      assert {:noreply, socket} =
               GreenAsh.Live.Screen.handle_event("keydown", %{"key" => "Escape"}, mounted)

      assert {:live, :redirect, %{to: "/cli"}} = socket.redirected
    end

    test "an ordinary resource still renders its real screen" do
      {:ok, mounted} = mount_list("org", "read")

      html = render_view(GreenAsh.Live.Subfile, mounted.assigns)

      refute html =~ "TENANT REQUIRED"
      assert html =~ "GREEN·ASH"
    end

    test "an actor stored for a tenant-required resource says so instead of vanishing" do
      # OnMount resolves the actor before every guard above, and used to
      # swallow this failure whole: nil actor, no word to the user.
      session = session(%{"slug" => "project", "id" => Ash.UUID.generate()})

      assert {:cont, mounted} = on_mount(session)
      assert mounted.assigns.actor == nil
      assert mounted.assigns.actor_notice =~ "requires a tenant"
    end

    test "the reason reaches the screen rather than dying in OnMount" do
      assert {:cont, mounted} = on_mount(session(%{"slug" => "project", "id" => "x"}))

      {:ok, menu} = GreenAsh.Live.Menu.mount(%{}, %{}, mounted)
      assert menu.assigns.message =~ "requires a tenant"
    end

    test "a stale id is reported too, not just the tenant case" do
      assert {:cont, mounted} = on_mount(session(%{"slug" => "org", "id" => Ash.UUID.generate()}))
      assert mounted.assigns.actor == nil
      assert mounted.assigns.actor_notice =~ "no org found"
    end

    test "a slug no longer exposed is reported" do
      assert {:cont, mounted} = on_mount(session(%{"slug" => "ghost", "id" => "1"}))
      assert mounted.assigns.actor_notice =~ ~s(no resource "ghost")
    end

    test "a working actor loads, with no notice" do
      org = Ash.create!(Org, %{slug: "acme"})

      assert {:cont, mounted} = on_mount(session(%{"slug" => "org", "id" => org.id}))
      assert mounted.assigns.actor.id == org.id
      assert mounted.assigns.actor_notice == nil
    end

    test "no actor at all is silence, not an error" do
      assert {:cont, mounted} = on_mount(session(nil))
      assert mounted.assigns.actor == nil
      assert mounted.assigns.actor_notice == nil
    end

    test "the menu flags the resource instead of hiding it" do
      assert {:ok, mounted} = GreenAsh.Live.Menu.mount(%{}, %{}, socket(%{}))

      details = Enum.map(mounted.assigns.options, & &1.detail)
      assert "Project · tenant required" in details
      assert "Org" in details
    end

    test "the flag survives drilling into the resource's action list" do
      {:ok, main} = GreenAsh.Live.Menu.mount(%{}, %{}, socket(%{}))
      n = Enum.find(main.assigns.options, &(&1.target == {:resource, Project})).n

      {:noreply, actions} =
        GreenAsh.Live.Menu.handle_event("select", %{"n" => to_string(n)}, main)

      assert actions.assigns.level == :resource
      assert actions.assigns.message =~ "requires a tenant"
    end

    test "drilling into an ordinary resource says nothing" do
      {:ok, main} = GreenAsh.Live.Menu.mount(%{}, %{}, socket(%{}))
      n = Enum.find(main.assigns.options, &(&1.target == {:resource, Org})).n

      {:noreply, actions} =
        GreenAsh.Live.Menu.handle_event("select", %{"n" => to_string(n)}, main)

      assert actions.assigns.message == ""
    end
  end
end
