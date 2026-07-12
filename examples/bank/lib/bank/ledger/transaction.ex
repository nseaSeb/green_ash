defmodule Bank.Ledger.Transaction do
  @moduledoc """
  Resource cobaye : exerce une relation (`belongs_to`) pour éprouver le rendu
  d'une clé étrangère (Ash.Type.UUID) et le tri/filtre sur des données liées.
  """
  use Ash.Resource,
    domain: Bank.Ledger,
    data_layer: AshPostgres.DataLayer

  resource do
    description "Transactions"
  end

  postgres do
    table "transactions"
    repo Bank.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :amount, :decimal do
      allow_nil? false
      public? true
    end

    attribute :memo, :string do
      public? true
    end

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :account, Bank.Ledger.Account do
      allow_nil? false
      attribute_writable? true
      public? true
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:account_id, :amount, :memo]
    end
  end
end
