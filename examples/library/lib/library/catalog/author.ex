defmodule Library.Catalog.Author do
  @moduledoc """
  Auteur d'un ou plusieurs livres (`has_many :books`).
  """
  use Ash.Resource,
    domain: Library.Catalog,
    data_layer: AshPostgres.DataLayer

  resource do
    description("Auteurs")
  end

  postgres do
    table("authors")
    repo(Library.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :name, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :country, :string do
      public?(true)
    end
  end

  relationships do
    has_many :books, Library.Catalog.Book
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      primary?(true)
      accept([:name, :country])
    end

    update :update do
      primary?(true)
      accept([:name, :country])
    end
  end
end
