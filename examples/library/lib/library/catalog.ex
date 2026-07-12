defmodule Library.Catalog do
  @moduledoc """
  Domaine de démonstration GreenAsh : une relation Author <-> Book, pour
  éprouver le rendu d'une clé étrangère et servir de répétition générale à
  `mix green_ash.install` sur une app qui n'a jamais connu la lib.
  """
  use Ash.Domain

  resources do
    resource(Library.Catalog.Author)
    resource(Library.Catalog.Book)
  end
end
