defmodule Library.Catalog do
  @moduledoc """
  GreenAsh demo domain: an Author <-> Book relationship, to test the
  rendering of a foreign key and serve as a dress rehearsal for
  `mix green_ash.install` on an app that has never known the lib.
  """
  use Ash.Domain

  resources do
    resource(Library.Catalog.Author)
    resource(Library.Catalog.Book)
  end
end
