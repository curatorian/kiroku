defmodule Kiroku.Repository.Community do
  use Ash.Resource,
    otp_app: :kiroku,
    domain: Kiroku.Repository,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "communities"
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
        :position,
        :parent_community_id,
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
    attribute :position, :integer, default: 0, public?: true
    attribute :is_active, :boolean, default: true, public?: true

    timestamps()
  end

  relationships do
    belongs_to :parent_community, __MODULE__, public?: true

    has_many :subcommunities, __MODULE__,
      destination_attribute: :parent_community_id,
      public?: true

    has_many :collections, Kiroku.Repository.Collection, public?: true
  end

  identities do
    identity :unique_handle, [:handle]
  end
end
