defmodule Kiroku.Repository.Collection do
  use Ash.Resource,
    otp_app: :kiroku,
    domain: Kiroku.Repository,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "collections"
    repo Kiroku.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :name,
        :handle,
        :short_description,
        :description,
        :logo_bitstream_id,
        :license_text,
        :position,
        :community_id,
        :is_active
      ]

      validate present(:name)
    end

    update :update do
      accept [
        :name,
        :handle,
        :short_description,
        :description,
        :logo_bitstream_id,
        :license_text,
        :position,
        :is_active
      ]
    end

    read :by_handle do
      argument :handle, :string, allow_nil?: false
      filter expr(handle == ^arg(:handle))
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if actor_attribute_equals(:user_type, :admin)
      authorize_if actor_attribute_equals(:user_type, :superadmin)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, allow_nil?: false, public?: true
    attribute :handle, :string, public?: true
    attribute :short_description, :string, public?: true
    attribute :description, :string, public?: true
    attribute :logo_bitstream_id, :uuid, public?: true
    attribute :license_text, :string, public?: true
    attribute :position, :integer, default: 0, public?: true
    attribute :is_active, :boolean, default: true, public?: true

    timestamps()
  end

  relationships do
    belongs_to :community, Kiroku.Repository.Community,
      allow_nil?: false,
      public?: true

    has_many :items, Kiroku.Repository.Item, public?: true
  end

  identities do
    identity :unique_handle, [:handle]
  end
end
