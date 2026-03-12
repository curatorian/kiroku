defmodule Kiroku.Access.RbacPolicy do
  use Ash.Resource,
    otp_app: :kiroku,
    domain: Kiroku.Access,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "rbac_policies"
    repo Kiroku.Repo

    custom_indexes do
      index [:resource_type, :resource_id]
      index [:group_id]
      index [:user_id]
    end
  end

  @resource_types ~w(Community Collection Item Bitstream)a
  @actions ~w(read write delete admin)a
  @policy_types ~w(custom embargo default)a

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :resource_type,
        :resource_id,
        :group_id,
        :user_id,
        :action,
        :start_date,
        :end_date,
        :policy_type
      ]
    end

    read :active_for_resource do
      argument :resource_type, :atom, allow_nil?: false
      argument :resource_id, :uuid, allow_nil?: false

      filter expr(
               resource_type == ^arg(:resource_type) and
                 resource_id == ^arg(:resource_id) and
                 (is_nil(start_date) or start_date <= now()) and
                 (is_nil(end_date) or end_date >= now())
             )
    end
  end

  validations do
    validate Kiroku.Access.RbacPolicy.Validations.ExactlyOnePrincipal
  end

  attributes do
    uuid_primary_key :id

    attribute :resource_type, :atom,
      constraints: [one_of: @resource_types],
      allow_nil?: false,
      public?: true

    attribute :resource_id, :uuid, allow_nil?: false, public?: true

    # Principal (exactly one of group_id or user_id must be set)
    attribute :group_id, :uuid, public?: true
    attribute :user_id, :uuid, public?: true

    attribute :action, :atom,
      constraints: [one_of: @actions],
      allow_nil?: false,
      public?: true

    attribute :start_date, :naive_datetime, public?: true
    attribute :end_date, :naive_datetime, public?: true

    attribute :policy_type, :atom,
      constraints: [one_of: @policy_types],
      default: :custom,
      public?: true

    timestamps()
  end
end
