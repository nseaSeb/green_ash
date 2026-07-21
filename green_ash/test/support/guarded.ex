defmodule GreenAsh.TestSupport.Guarded do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource GreenAsh.TestSupport.Secret
    resource GreenAsh.TestSupport.Entry
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
