defmodule GreenAsh.RefusalTest do
  @moduledoc """
  The console must answer, never crash.

  Each case below reached `mount/3` or a `handle_event/3` and raised before:
  a policy-denied read, a read Ash insists on paginating, an action name the
  URL invented, a filter value that will not cast, a sort column off the
  wire. A raise there is a 500 — and for the forbidden read, a 500 on exactly
  the thing this console is built to show you.
  """
  use ExUnit.Case, async: true

  alias GreenAsh.Live.{Screen, Subfile}
  alias GreenAsh.Registry
  alias GreenAsh.TestSupport.{Entry, Guarded, Secret}

  @domains [Guarded]

  defp socket(assigns \\ %{}) do
    %Phoenix.LiveView.Socket{
      assigns:
        Map.merge(
          %{__changed__: %{}, domains: @domains, base: "/cli", actor: nil, actor_notice: nil},
          assigns
        )
    }
  end

  defp render_view(module, assigns) do
    assigns
    |> Map.put(:__changed__, nil)
    |> module.render()
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  defp mount_list(slug, action, assigns \\ %{}) do
    Subfile.mount(%{"resource" => slug, "action" => action}, %{}, socket(assigns))
  end

  describe "a read denied by a policy" do
    test "the read really is denied — the guard is not testing a no-op" do
      assert {:error, %Ash.Error.Forbidden{}} =
               Secret |> Ash.Query.for_read(:read, %{}, actor: nil) |> Ash.read(actor: nil)
    end

    test "the console reports it instead of raising" do
      assert {:ok, mounted} = mount_list("secret", "read")

      assert mounted.assigns.rows == []
      assert mounted.assigns.read_error =~ "Forbidden"
      # The way out is a command, so name it: a bare "forbidden" leaves the
      # reader with no next move.
      assert mounted.assigns.read_error =~ ":actor <resource> <id>"
    end

    test "the reason reaches the screen, not just the assigns" do
      {:ok, mounted} = mount_list("secret", "read")

      assert render_view(Subfile, mounted.assigns) =~ "Forbidden"
    end

    test "an authorized actor sees the rows, and no error" do
      Ash.create!(Secret, %{label: "classified"}, authorize?: false)
      actor = Ash.create!(Secret, %{label: "agent"}, authorize?: false)

      assert {:ok, mounted} = mount_list("secret", "read", %{actor: actor})

      assert mounted.assigns.read_error == nil
      assert length(mounted.assigns.rows) == 2
    end

    test "the actor's own name is in the refusal, so it reads as a verdict on the actor" do
      {:ok, mounted} = mount_list("secret", "read")

      assert mounted.assigns.read_error =~ "anonymous"
    end
  end

  describe "a read Ash insists on paginating" do
    test "Ash answers with a page struct, not a list" do
      assert {:ok, %Ash.Page.Offset{}} =
               Entry |> Ash.Query.for_read(:read, %{}) |> Ash.read(page: [limit: 5, offset: 0])
    end

    test "Registry.paginated? tells the two kinds of read apart" do
      # `defaults [:read]` declares pagination; a hand-written `read` block
      # does not — so this cannot be assumed either way.
      assert Registry.paginated?(Registry.action(Entry, :read))
      assert Registry.paginated?(Registry.action(Secret, :read))
      refute Registry.paginated?(Registry.action(GreenAsh.TestSupport.Account, :search))
    end

    test "the console lists it rather than raising on length/1" do
      Ash.create!(Entry, %{title: "first"})
      Ash.create!(Entry, %{title: "second"})

      assert {:ok, mounted} = mount_list("entry", "read")

      assert mounted.assigns.read_error == nil
      assert length(mounted.assigns.rows) == 2
      refute mounted.assigns.has_next
    end

    test "paging still works through Ash's own page options" do
      for n <- 1..21, do: Ash.create!(Entry, %{title: "row #{n}"})

      {:ok, mounted} = mount_list("entry", "read")
      assert length(mounted.assigns.rows) == 20
      assert mounted.assigns.has_next

      {:noreply, next} = Subfile.handle_event("page", %{"dir" => "next"}, mounted)
      assert length(next.assigns.rows) == 1
      refute next.assigns.has_next
    end
  end

  describe "an action name the URL invented" do
    test "Registry.action returns nil rather than raising on an unknown atom" do
      assert Registry.action(Secret, "no_such_action_anywhere") == nil
    end

    test "the list says so" do
      assert {:ok, mounted} = mount_list("secret", "no_such_action_anywhere")

      assert mounted.assigns.notice.kind == :no_action
      assert render_view(Subfile, mounted.assigns) =~ "UNKNOWN ACTION"
    end

    test "the action screen says so too" do
      assert {:ok, mounted} =
               Screen.mount(
                 %{"resource" => "secret", "action" => "no_such_action_anywhere"},
                 %{},
                 socket()
               )

      assert mounted.assigns.notice.kind == :no_action
      assert render_view(Screen, mounted.assigns) =~ "UNKNOWN ACTION"
    end

    test "Escape from the notice still returns to the menu" do
      {:ok, mounted} = mount_list("secret", "no_such_action_anywhere")

      assert {:noreply, socket} = Subfile.handle_event("keydown", %{"key" => "Escape"}, mounted)
      assert {:live, :redirect, %{to: "/cli"}} = socket.redirected
    end
  end

  describe "a non-read action asked to behave like a list" do
    test "the list refuses it by type" do
      assert {:ok, mounted} = mount_list("secret", "create")

      assert mounted.assigns.notice.kind == :not_readable
      assert mounted.assigns.notice.type == :create

      html = render_view(Subfile, mounted.assigns)
      assert html =~ "NOT A LIST"
      assert html =~ "create"
    end
  end

  # Account's `:search` read takes a real `:holder` argument, so this is the
  # actual path a user walks: type something the argument cannot hold and the
  # filter form posts it on change.
  describe "a filter value that will not cast" do
    defp mount_search do
      Subfile.mount(
        %{"resource" => "account", "action" => "search"},
        %{},
        socket(%{domains: [GreenAsh.TestSupport.Bank]})
      )
    end

    test "the error lands on the status line and the screen survives" do
      {:ok, mounted} = mount_search()

      assert {:noreply, filtered} =
               Subfile.handle_event("filter", %{"filter" => %{"holder" => %{"a" => 1}}}, mounted)

      assert filtered.assigns.rows == []
      assert filtered.assigns.read_error =~ "Read failed"
      assert filtered.assigns.read_error =~ "holder"
      # Ash's message carries a multi-line breadcrumb trail; the status line
      # holds one line.
      refute filtered.assigns.read_error =~ "Bread Crumbs"
      refute filtered.assigns.read_error =~ "\n"
    end

    test "a later good read clears the error" do
      Ash.create!(GreenAsh.TestSupport.Account, %{holder: "Ada"}, action: :open)
      {:ok, mounted} = mount_search()

      {:noreply, broken} =
        Subfile.handle_event("filter", %{"filter" => %{"holder" => %{"a" => 1}}}, mounted)

      assert broken.assigns.read_error

      {:noreply, fixed} =
        Subfile.handle_event("filter", %{"filter" => %{"holder" => "Ada"}}, broken)

      assert fixed.assigns.read_error == nil
      assert [%{holder: "Ada"}] = fixed.assigns.rows
    end
  end

  describe "a sort column off the wire" do
    test "an unknown column is ignored, not turned into an atom" do
      actor = Ash.create!(Secret, %{label: "agent"}, authorize?: false)
      {:ok, mounted} = mount_list("secret", "read", %{actor: actor})

      assert {:noreply, socket} =
               Subfile.handle_event("sort", %{"col" => "not_a_column_at_all"}, mounted)

      assert socket.assigns.sort == nil
    end

    test "a real column still sorts" do
      actor = Ash.create!(Secret, %{label: "agent"}, authorize?: false)
      {:ok, mounted} = mount_list("secret", "read", %{actor: actor})

      {:noreply, socket} = Subfile.handle_event("sort", %{"col" => "label"}, mounted)
      assert socket.assigns.sort == {:label, :asc}
    end
  end
end
