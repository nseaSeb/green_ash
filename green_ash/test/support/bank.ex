defmodule GreenAsh.TestSupport.Bank do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource GreenAsh.TestSupport.Account
  end
end

defmodule GreenAsh.TestSupport.Account do
  @moduledoc false
  use Ash.Resource,
    domain: GreenAsh.TestSupport.Bank,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer]

  # Table ETS privée au process : isolation automatique entre tests async.
  ets do
    private? true
  end

  resource do
    description "Comptes bancaires"
  end

  attributes do
    uuid_primary_key :id
    attribute :holder, :string, allow_nil?: false, public?: true
    attribute :balance, :decimal, default: Decimal.new(0), allow_nil?: false, public?: true

    attribute :status, :atom,
      constraints: [one_of: [:open, :frozen, :closed]],
      default: :open,
      public?: true

    attribute :opened_on, :date, public?: true
  end

  policies do
    policy action_type(:destroy) do
      authorize_if actor_present()
    end

    policy always() do
      authorize_if always()
    end
  end

  actions do
    defaults [:read, :destroy]

    read :search do
      argument :holder, :string, allow_nil?: true
      filter expr(is_nil(^arg(:holder)) or contains(holder, ^arg(:holder)))
    end

    create :open do
      description "Ouvrir un compte"
      primary? true
      accept [:holder, :opened_on]
      argument :initial_deposit, :decimal, allow_nil?: false, default: Decimal.new(0)

      change fn cs, _ ->
        Ash.Changeset.change_attribute(
          cs,
          :balance,
          Ash.Changeset.get_argument(cs, :initial_deposit)
        )
      end
    end

    update :credit do
      description "Créditer un compte"
      accept []
      require_atomic? false
      argument :amount, :decimal, allow_nil?: false

      change fn cs, _ ->
        case Ash.Changeset.get_argument(cs, :amount) do
          nil ->
            cs

          amount ->
            Ash.Changeset.change_attribute(
              cs,
              :balance,
              Decimal.add(cs.data.balance || Decimal.new(0), amount)
            )
        end
      end
    end
  end
end
