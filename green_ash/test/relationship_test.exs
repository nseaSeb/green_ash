defmodule GreenAsh.RelationshipTest do
  @moduledoc """
  A `belongs_to` should be a choice, not a UUID you paste.

  The action screen rendered a foreign key as what it is underneath — a text
  box wanting a raw id — so filling one in meant leaving the console, listing
  the other resource, copying an id, and coming back. The field now offers the
  related records.

  It offers them only when it honestly can: the read is real, so it can be
  refused, unbounded, or impossible. In each of those cases the field stays
  the id box it was, because an empty select reads as "there are none".
  """
  use ExUnit.Case, async: true

  alias GreenAsh.{Field, Registry}
  alias GreenAsh.Live.Screen
  alias GreenAsh.TestSupport.{Author, Book, Secret, Shelf}

  defp socket(assigns \\ %{}) do
    %Phoenix.LiveView.Socket{
      assigns:
        Map.merge(
          %{
            __changed__: %{},
            domains: [Shelf],
            base: "/cli",
            tenant: nil,
            actor: nil,
            actor_notice: nil
          },
          assigns
        )
    }
  end

  defp mount_create(assigns \\ %{}) do
    {:ok, socket} =
      Screen.mount(%{"resource" => "book", "action" => "create"}, %{}, socket(assigns))

    socket
  end

  defp spec(socket, name), do: Enum.find(socket.assigns.specs, &(&1.name == name))

  defp render(socket) do
    socket.assigns
    |> Map.put(:__changed__, nil)
    |> Screen.render()
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  describe "introspection" do
    test "specs/2 marks the foreign key with its relationship, and reads nothing" do
      specs = Field.specs(Book, Registry.action(Book, :create))

      assert %{name: :author} = Enum.find(specs, &(&1.name == :author_id)).relationship
      # Still the plain widget: specs/2 does not touch data, so it cannot yet
      # know whether a choice can be offered.
      assert Enum.find(specs, &(&1.name == :author_id)).input_type == "text"
      assert Enum.find(specs, &(&1.name == :title)).relationship == nil
    end
  end

  describe "when the related records can be read" do
    test "the field becomes a select of them" do
      Ash.create!(Author, %{name: "Ursula Le Guin"})
      Ash.create!(Author, %{name: "Octavia Butler"})

      spec = mount_create() |> spec(:author_id)

      assert spec.input_type == "select"
      assert length(spec.options) == 2
    end

    test "each option names the record and enough id to disambiguate" do
      author = Ash.create!(Author, %{name: "Ursula Le Guin"})

      [{label, value}] = mount_create() |> spec(:author_id) |> Map.fetch!(:options)

      assert label =~ "Ursula Le Guin"
      assert label =~ String.slice(author.id, 0, 8)
      assert value == author.id
    end

    test "the select reaches the screen, labelled by the relationship" do
      Ash.create!(Author, %{name: "Ursula Le Guin"})

      html = mount_create() |> render()

      assert html =~ ~s(<select id="form_author_id")
      assert html =~ "Ursula Le Guin"
      # "Author", not "Author id": the picker shows records, not columns.
      assert html =~ ">Author<"
    end

    test "no records yet still gives a select, just an empty one" do
      spec = mount_create() |> spec(:author_id)

      assert spec.input_type == "select"
      assert spec.options == []
    end

    test "a plain attribute is untouched" do
      assert mount_create() |> spec(:title) |> Map.fetch!(:input_type) == "text"
    end
  end

  describe "when a choice cannot honestly be offered" do
    test "a read the actor may not perform leaves the id box" do
      # Secret's policy demands an actor; the console is anonymous here.
      spec = mount_create() |> spec(:vault_id)

      assert spec.input_type == "text"
      assert spec.options == nil
    end

    test "the same field becomes a select once the actor may read it" do
      actor = Ash.create!(Secret, %{label: "agent"}, authorize?: false)
      Ash.create!(Secret, %{label: "dossier"}, authorize?: false)

      spec = mount_create(%{actor: actor}) |> spec(:vault_id)

      assert spec.input_type == "select"
      assert length(spec.options) == 2
    end

    test "a destination needing a tenant leaves the id box" do
      # The console has no tenant to set, so the read would be refused.
      assert Registry.tenant_required?(GreenAsh.TestSupport.Project)

      assert mount_create() |> spec(:project_id) |> Map.fetch!(:input_type) == "text"
    end

    test "more related records than a select can usefully hold leaves the id box" do
      # 101 authors: past the cap, so the field stays something you can paste
      # an id into rather than a list nobody can scroll.
      for n <- 1..101, do: Ash.create!(Author, %{name: "Author #{n}"})

      assert mount_create() |> spec(:author_id) |> Map.fetch!(:input_type) == "text"
    end

    test "exactly at the cap the select is still offered" do
      for n <- 1..100, do: Ash.create!(Author, %{name: "Author #{n}"})

      spec = mount_create() |> spec(:author_id)

      assert spec.input_type == "select"
      assert length(spec.options) == 100
    end
  end
end
