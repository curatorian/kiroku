defmodule Kiroku.Repository.ItemExaminer do
  use Ash.Resource,
    otp_app: :kiroku,
    domain: Kiroku.Repository,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "item_examiners"
    repo Kiroku.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:examiner_name, :examiner_nip, :sequence, :item_id]
      validate present(:examiner_name)
    end

    create :import do
      accept [:examiner_name, :examiner_nip, :sequence, :item_id]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :examiner_name, :string, allow_nil?: false, public?: true
    attribute :examiner_nip, :string, public?: true
    attribute :sequence, :integer, default: 1, public?: true

    timestamps()
  end

  relationships do
    belongs_to :item, Kiroku.Repository.Item,
      allow_nil?: false,
      public?: true
  end
end
