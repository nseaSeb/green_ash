defmodule Bank.Ledger do
  @moduledoc """
  Domaine métier "cobaye" servant de banc de test au renderer CLI.
  """
  use Ash.Domain

  resources do
    resource Bank.Ledger.Account
  end
end
