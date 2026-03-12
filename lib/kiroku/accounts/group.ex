defmodule Kiroku.Accounts.Group do
  use Ash.Resource,
    otp_app: :kiroku,
    domain: Kiroku.Accounts,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "groups"
    repo Kiroku.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name, :description, :is_system]
      validate present(:name)
    end

    update :update do
      accept [:name, :description]
    end

    read :by_name do
      argument :name, :string, allow_nil?: false
      get? true
      filter expr(name == ^arg(:name))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, allow_nil?: false, public?: true
    attribute :description, :string, public?: true
    attribute :is_system, :boolean, default: false, public?: true

    timestamps()
  end

  relationships do
    has_many :group_memberships, Kiroku.Accounts.GroupMembership, public?: true

    many_to_many :users, Kiroku.Accounts.User do
      through Kiroku.Accounts.GroupMembership
      source_attribute_on_join_resource :group_id
      destination_attribute_on_join_resource :user_id
      public? true
    end
  end

  identities do
    identity :unique_name, [:name]
  end
end
