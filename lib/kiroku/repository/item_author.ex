defmodule Kiroku.Repository.ItemAuthor do
  use Ash.Resource,
    otp_app: :kiroku,
    domain: Kiroku.Repository,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "item_authors"
    repo Kiroku.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:author_name, :author_email, :author_affiliation, :orcid_id, :sequence, :item_id]
      validate present(:author_name)
    end

    create :import do
      accept [:author_name, :author_email, :author_affiliation, :orcid_id, :sequence, :item_id]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :author_name, :string, allow_nil?: false, public?: true
    attribute :author_email, :string, public?: true
    attribute :author_affiliation, :string, public?: true
    attribute :orcid_id, :string, public?: true
    attribute :sequence, :integer, default: 1, public?: true

    timestamps()
  end

  relationships do
    belongs_to :item, Kiroku.Repository.Item,
      allow_nil?: false,
      public?: true
  end
end
