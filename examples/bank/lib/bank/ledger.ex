defmodule Bank.Ledger do
  @moduledoc """
  "Guinea pig" business domain serving as a test bench for the CLI renderer.
  """
  use Ash.Domain

  resources do
    resource Bank.Ledger.Account
    resource Bank.Ledger.Transaction
  end
end
