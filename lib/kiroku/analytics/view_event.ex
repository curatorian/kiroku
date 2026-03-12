defmodule Kiroku.Analytics.ViewEvent do
  use Ash.Resource,
    otp_app: :kiroku,
    domain: Kiroku.Analytics,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "view_events"
    repo Kiroku.Repo

    custom_indexes do
      index [:resource_type, :resource_id]
      index [:inserted_at]
    end
  end

  @resource_types ~w(Item Bitstream)a

  actions do
    defaults [:read]

    create :track do
      accept [
        :resource_type,
        :resource_id,
        :ip_hash,
        :user_agent,
        :referrer,
        :country_code,
        :user_id
      ]
    end
  end

  policies do
    policy action(:track) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if actor_attribute_equals(:user_type, :admin)
      authorize_if actor_attribute_equals(:user_type, :superadmin)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :resource_type, :atom,
      constraints: [one_of: @resource_types],
      allow_nil?: false,
      public?: true

    attribute :resource_id, :uuid, allow_nil?: false, public?: true
    attribute :ip_hash, :string, public?: true
    attribute :user_agent, :string, public?: true
    attribute :referrer, :string, public?: true
    attribute :country_code, :string, public?: true

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :user, Kiroku.Accounts.User,
      allow_nil?: true,
      public?: true
  end
end
