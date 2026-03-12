defmodule Kiroku.Repository.ItemMetadata do
  use Ash.Resource,
    otp_app: :kiroku,
    domain: Kiroku.Repository,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "item_metadata"
    repo Kiroku.Repo

    custom_indexes do
      index [:field_schema, :field_element]
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :field_schema,
        :field_element,
        :field_qualifier,
        :field_value,
        :language,
        :confidence,
        :place,
        :item_id
      ]
    end

    create :import do
      accept [
        :field_schema,
        :field_element,
        :field_qualifier,
        :field_value,
        :language,
        :confidence,
        :place,
        :item_id
      ]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :field_schema, :string, allow_nil?: false, public?: true
    attribute :field_element, :string, allow_nil?: false, public?: true
    attribute :field_qualifier, :string, public?: true
    attribute :field_value, :string, allow_nil?: false, public?: true
    attribute :language, :string, public?: true
    attribute :confidence, :integer, default: 0, public?: true
    attribute :place, :integer, default: 1, public?: true

    timestamps()
  end

  relationships do
    belongs_to :item, Kiroku.Repository.Item,
      allow_nil?: false,
      public?: true
  end
end
