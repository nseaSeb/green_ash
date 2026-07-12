defmodule LibraryWeb.ConsoleTest do
  @moduledoc """
  Tests d'intégration de la console GreenAsh, montée par `mix green_ash.install`
  (exécuté réellement sur cette app, pas écrit à la main). Éprouve la relation
  Author <-> Book : rendu de la clé étrangère, filtre, création liée.
  """
  use LibraryWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Library.Catalog.{Author, Book}

  defp create_author(name) do
    Author
    |> Ash.Changeset.for_create(:create, %{name: name})
    |> Ash.create!()
  end

  test "le menu découvre les deux resources du domaine", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/cli")
    assert html =~ "Auteurs"
    assert html =~ "Livres"
  end

  test "création d'un Author, puis d'un Book lié (author_id en champ texte)", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/cli/r/author/a/create")

    view
    |> form("form[phx-submit='submit']",
      form: %{"name" => "Ursula K. Le Guin", "country" => "US"}
    )
    |> render_submit()

    author = Enum.find(Ash.read!(Author, authorize?: false), &(&1.name == "Ursula K. Le Guin"))
    assert author

    {:ok, view2, html2} = live(conn, "/cli/r/book/a/create")
    # Ash.Type.UUID (clé étrangère de belongs_to) doit se rendre en texte.
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

  test "liste des Books avec filtre par titre (read :by_title)", %{conn: conn} do
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
