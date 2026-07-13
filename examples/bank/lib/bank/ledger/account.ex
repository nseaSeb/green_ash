defmodule Bank.Ledger.Account do
  @moduledoc """
  Guinea pig resource: covers several scalar types (string, decimal, enum,
  date) and various actions (create/read/destroy + business actions with
  arguments) to exercise the CLI renderer's type -> widget mapper.
  """
  use Ash.Resource,
    domain: Bank.Ledger,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  resource do
    description "Bank accounts"
  end

  postgres do
    table "accounts"
    repo Bank.Repo
  end

  # Policy demonstration: deleting an account requires an actor; everything
  # else is authorized. The console passes the chosen actor via `:actor`.
  policies do
    policy action_type(:destroy) do
      authorize_if actor_present()
    end

    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :holder, :string do
      allow_nil? false
      public? true
    end

    attribute :balance, :decimal do
      allow_nil? false
      default Decimal.new(0)
      public? true
    end

    attribute :status, :atom do
      constraints one_of: [:open, :frozen, :closed]
      default :open
      allow_nil? false
      public? true
    end

    attribute :opened_on, :date do
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  actions do
    defaults [:read, :destroy]

    # Read with argument: demonstrates the query-side list filter.
    read :search do
      description "Search by holder"
      argument :holder, :string, allow_nil?: true
      filter expr(is_nil(^arg(:holder)) or contains(holder, ^arg(:holder)))
    end

    # Business action: open an account with an initial deposit (argument).
    create :open do
      description "Open an account"
      primary? true
      accept [:holder, :opened_on]

      argument :initial_deposit, :decimal do
        allow_nil? false
        default Decimal.new(0)
      end

      change fn changeset, _context ->
        deposit = Ash.Changeset.get_argument(changeset, :initial_deposit)
        Ash.Changeset.change_attribute(changeset, :balance, deposit)
      end
    end

    # Business action: credit an existing account (update + argument).
    update :credit do
      description "Credit an account"
      accept []
      require_atomic? false

      argument :amount, :decimal do
        allow_nil? false
      end

      change fn changeset, _context ->
        # `amount` is nil while the form is being built (before input): the
        # calculation is only applied once it is present.
        case Ash.Changeset.get_argument(changeset, :amount) do
          nil ->
            changeset

          amount ->
            current = changeset.data.balance || Decimal.new(0)
            Ash.Changeset.change_attribute(changeset, :balance, Decimal.add(current, amount))
        end
      end
    end
  end
end
