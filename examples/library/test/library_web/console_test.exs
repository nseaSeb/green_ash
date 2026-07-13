defmodule LibraryWeb.ConsoleTest do
  @moduledoc """
  Integration tests for the GreenAsh console, mounted by
  `mix green_ash.install` (actually run on this app, not hand-written).
  Exercises the Author <-> Book relationship: foreign key rendering, filter,
  linked creation.
  """
  use LibraryWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Library.Catalog.{Author, Book}

  defp create_author(name) do
    Author
    |> Ash.Changeset.for_create(:create, %{name: name})
    |> Ash.create!()
  end

  test "the menu discovers both resources of the domain", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/cli")
    assert html =~ "Authors"
    assert html =~ "Books"
  end

  test "creation of an Author, then a linked Book (author_id as a text field)", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/cli/r/author/a/create")

    view
    |> form("form[phx-submit='submit']",
      form: %{"name" => "Ursula K. Le Guin", "country" => "US"}
    )
    |> render_submit()

    author = Enum.find(Ash.read!(Author, authorize?: false), &(&1.name == "Ursula K. Le Guin"))
    assert author

    {:ok, view2, html2} = live(conn, "/cli/r/book/a/create")
    # Ash.Type.UUID (belongs_to foreign key) must render as text.
    assert html2 =~ ~s(type="text" id="form_author_id" name="form[author_id]")

    view2
    |> form("form[phx-submit='submit']",
      form: %{"title" => "The Left Hand of Darkness", "author_id" => author.id}
    )
    |> render_submit()

    assert Enum.any?(
             Ash.read!(Book, authorize?: false),
             &(&1.title == "The Left Hand of Darkness" and &1.author_id == author.id)
           )
  end

  test "list of Books with filter by title (read :by_title)", %{conn: conn} do
    author = create_author("Isaac Asimov")

    Book
    |> Ash.Changeset.for_create(:create, %{title: "Foundation", author_id: author.id})
    |> Ash.create!()

    Book
    |> Ash.Changeset.for_create(:create, %{title: "I, Robot", author_id: author.id})
    |> Ash.create!()

    {:ok, view, html} = live(conn, "/cli/r/book/list/by_title")
    assert html =~ "Foundation"
    assert html =~ "I, Robot"

    filtered =
      view
      |> form("form.crt-filter", %{"filter" => %{"title" => "Found"}})
      |> render_change()

    assert filtered =~ "Foundation"
    refute filtered =~ "I, Robot"
  end
end
