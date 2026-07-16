defmodule GreenAsh.TestSupport.Saas do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource GreenAsh.TestSupport.Project
    resource GreenAsh.TestSupport.Plan
    resource GreenAsh.TestSupport.Org
  end
end

defmodule GreenAsh.TestSupport.Project do
  @moduledoc false
  use Ash.Resource,
    domain: GreenAsh.TestSupport.Saas,
    data_layer: Ash.DataLayer.Ets

  ets do
    private? true
  end

  # Attribute strategy, NOT global?: this is the exact shape that
  # Ash.Actions.Read.validate_multitenancy/1 rejects without a tenant.
  multitenancy do
    strategy :attribute
    attribute :org_id
  end

  resource do
    description "Tenant-scoped projects"
  end

  attributes do
    uuid_primary_key :id
    attribute :org_id, :string, allow_nil?: false, public?: true
    attribute :name, :string, allow_nil?: false, public?: true
  end

  actions do
    defaults [:read, :destroy, create: [:org_id, :name]]
  end
end

defmodule GreenAsh.TestSupport.Plan do
  @moduledoc false
  use Ash.Resource,
    domain: GreenAsh.TestSupport.Saas,
    data_layer: Ash.DataLayer.Ets

  ets do
    private? true
  end

  # Multitenant but global?: Ash allows an untenanted read, so the console
  # must NOT block it. This is the escape hatch in validate_multitenancy/1.
  multitenancy do
    strategy :attribute
    attribute :org_id
    global? true
  end

  attributes do
    uuid_primary_key :id
    attribute :org_id, :string, public?: true
    attribute :name, :string, allow_nil?: false, public?: true
  end

  actions do
    defaults [:read, create: [:org_id, :name]]
  end
end

defmodule GreenAsh.TestSupport.Org do
  @moduledoc false
  use Ash.Resource,
    domain: GreenAsh.TestSupport.Saas,
    data_layer: Ash.DataLayer.Ets

  ets do
    private? true
  end

  # Sits in the same domain as Project but declares no multitenancy: proves
  # the guard singles out the constrained resource rather than the domain.
  attributes do
    uuid_primary_key :id
    attribute :slug, :string, allow_nil?: false, public?: true
  end

  actions do
    defaults [:read, create: [:slug]]
  end
end
