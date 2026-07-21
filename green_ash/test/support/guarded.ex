defmodule GreenAsh.TestSupport.Guarded do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource GreenAsh.TestSupport.Secret
    resource GreenAsh.TestSupport.Entry
    resource GreenAsh.TestSupport.Capped
  end
end

defmodule GreenAsh.TestSupport.Secret do
  @moduledoc """
  A resource whose *read* is denied without an actor.

  `GreenAsh.TestSupport.Account` gates only its destroy and lets everything
  else through (`authorize_if always()`), so it never exercises the case this
  console exists for: a read the current actor may not perform.
  """
  use Ash.Resource,
    domain: GreenAsh.TestSupport.Guarded,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer]

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :label, :string, public?: true
  end

  policies do
    policy always() do
      authorize_if actor_present()
    end
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:label]
    end
  end
end

defmodule GreenAsh.TestSupport.Entry do
  @moduledoc """
  A resource whose read declares `pagination required?: true` — Ash then
  answers with an `Ash.Page.*` struct instead of a list, and refuses a read
  that carries no page options.
  """
  use Ash.Resource,
    domain: GreenAsh.TestSupport.Guarded,
    data_layer: Ash.DataLayer.Ets

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
  end

  actions do
    create :create do
      primary? true
      accept [:title]
    end

    read :read do
      primary? true
      pagination offset?: true, required?: true, default_limit: 10
    end
  end
end

defmodule GreenAsh.TestSupport.Capped do
  @moduledoc """
  Required pagination with a `max_page_size` below the console's page size.

  Ash caps a `:page` read at `max_page_size` and returns a short page rather
  than an error, so a console asking for more than the cap gets fewer rows
  than it thinks — and, if it sizes its page off its own constant, concludes
  there is no next page. That loses records with no visible symptom.
  """
  use Ash.Resource,
    domain: GreenAsh.TestSupport.Guarded,
    data_layer: Ash.DataLayer.Ets

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :n, :integer, public?: true
  end

  actions do
    create :create do
      primary? true
      accept [:n]
    end

    read :read do
      primary? true
      pagination offset?: true, required?: true, default_limit: 5, max_page_size: 10
    end
  end
end

# Two resources whose module names end in the same segment, in two domains —
# the shape that gave both the slug "account" and made the second resolve to
# the first.
defmodule GreenAsh.TestSupport.Twin.Bank do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource GreenAsh.TestSupport.Twin.Bank.Account
  end
end

defmodule GreenAsh.TestSupport.Twin.Bank.Account do
  @moduledoc false
  use Ash.Resource, domain: GreenAsh.TestSupport.Twin.Bank, data_layer: Ash.DataLayer.Ets

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
  end

  actions do
    defaults [:read]
  end
end

defmodule GreenAsh.TestSupport.Twin.Sales do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource GreenAsh.TestSupport.Twin.Sales.Account
  end
end

defmodule GreenAsh.TestSupport.Twin.Sales.Account do
  @moduledoc false
  use Ash.Resource, domain: GreenAsh.TestSupport.Twin.Sales, data_layer: Ash.DataLayer.Ets

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
  end

  actions do
    defaults [:read]
  end
end
