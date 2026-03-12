defmodule Kiroku.Accounts.GroupMembership do
  use Ash.Resource,
    otp_app: :kiroku,
    domain: Kiroku.Accounts,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "group_memberships"
    repo Kiroku.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:user_id, :group_id, :expires_at]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :expires_at, :naive_datetime, public?: true

    timestamps()
  end

  relationships do
    belongs_to :user, Kiroku.Accounts.User,
      allow_nil?: false,
      public?: true

    belongs_to :group, Kiroku.Accounts.Group,
      allow_nil?: false,
      public?: true
  end

  identities do
    identity :unique_user_group, [:user_id, :group_id]
  end
end
