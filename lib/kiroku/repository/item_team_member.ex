defmodule Kiroku.Repository.ItemTeamMember do
  use Ash.Resource,
    otp_app: :kiroku,
    domain: Kiroku.Repository,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "item_team_members"
    repo Kiroku.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:member_name, :member_nim, :program_study, :role, :sequence, :item_id]
      validate present(:member_name)
    end

    create :import do
      accept [:member_name, :member_nim, :program_study, :role, :sequence, :item_id]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :member_name, :string, allow_nil?: false, public?: true
    attribute :member_nim, :string, public?: true
    attribute :program_study, :string, public?: true
    attribute :role, :string, public?: true
    attribute :sequence, :integer, default: 1, public?: true

    timestamps()
  end

  relationships do
    belongs_to :item, Kiroku.Repository.Item,
      allow_nil?: false,
      public?: true
  end
end
