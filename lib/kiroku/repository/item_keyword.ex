defmodule Kiroku.Repository.ItemKeyword do
  use Ash.Resource,
    otp_app: :kiroku,
    domain: Kiroku.Repository,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "item_keywords"
    repo Kiroku.Repo

    custom_indexes do
      index [:keyword]
      index [:item_id]
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:keyword, :language, :item_id]
      validate present(:keyword)
    end

    create :import do
      accept [:keyword, :language, :item_id]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :keyword, :string, allow_nil?: false, public?: true
    attribute :language, :string, default: "id", public?: true

    timestamps()
  end

  relationships do
    belongs_to :item, Kiroku.Repository.Item,
      allow_nil?: false,
      public?: true
  end
end
