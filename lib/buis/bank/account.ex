defmodule Buis.Bank.Account do
  @moduledoc """
  Resource cobaye : couvre plusieurs types scalaires (string, decimal, enum, date)
  et des actions variées (create/read/destroy + actions métier avec arguments)
  pour exercer le mapper type -> widget du renderer CLI.
  """
  use Ash.Resource,
    domain: Buis.Bank,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  resource do
    description "Comptes bancaires"
  end

  postgres do
    table "accounts"
    repo Buis.Repo
  end

  # Démonstration des policies : supprimer un compte exige un acteur ;
  # le reste est autorisé. La console passe l'acteur choisi via `:actor`.
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

    # Read avec argument : démontre le filtre de liste côté requête.
    read :search do
      description "Rechercher par titulaire"
      argument :holder, :string, allow_nil?: true
      filter expr(is_nil(^arg(:holder)) or contains(holder, ^arg(:holder)))
    end

    # Action métier : ouvrir un compte avec un dépôt initial (argument).
    create :open do
      description "Ouvrir un compte"
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

    # Action métier : créditer un compte existant (update + argument).
    update :credit do
      description "Créditer un compte"
      accept []
      require_atomic? false

      argument :amount, :decimal do
        allow_nil? false
      end

      change fn changeset, _context ->
        # `amount` est nil pendant la construction du formulaire (avant saisie) :
        # on n'applique le calcul que lorsqu'il est présent.
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
