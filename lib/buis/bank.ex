defmodule Buis.Bank do
  @moduledoc """
  Domaine métier "cobaye" servant de banc de test au renderer CLI.
  """
  use Ash.Domain

  resources do
    resource Buis.Bank.Account
  end
end
