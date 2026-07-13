defmodule Bank.Ledger.Transaction do
  @moduledoc """
  Guinea pig resource: exercises a relationship (`belongs_to`) to test the
  rendering of a foreign key (Ash.Type.UUID) and sorting/filtering on related
  data.
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
