defmodule Library.Catalog.Book do
  @moduledoc """
  Livre, lié à un auteur (`belongs_to :author`) — exerce le rendu de la clé
  étrangère (Ash.Type.UUID) et le filtre par titre.
  """
  use Ash.Resource,
    domain: Library.Catalog,
    data_layer: AshPostgres.DataLayer

  resource do
    description("Livres")
  end

  postgres do
    table("books")
    repo(Library.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :title, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :published_on, :date do
      public?(true)
    end
  end

  relationships do
    belongs_to :author, Library.Catalog.Author do
      allow_nil?(false)
      attribute_writable?(true)
      public?(true)
    end
  end

  actions do
    defaults([:read, :destroy])

    read :by_title do
      description("Rechercher par titre")
      argument(:title, :string, allow_nil?: true)
      filter(expr(is_nil(^arg(:title)) or contains(title, ^arg(:title))))
    end

    create :create do
      primary?(true)
      accept([:title, :published_on, :author_id])
    end

    update :update do
      primary?(true)
      accept([:title, :published_on])
    end
  end
end
