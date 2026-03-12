defmodule Kiroku.Repository.ItemAdvisor do
  use Ash.Resource,
    otp_app: :kiroku,
    domain: Kiroku.Repository,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "item_advisors"
    repo Kiroku.Repo
  end

  @advisor_roles ~w(main_advisor co_advisor external industry law_clinic curator promotor)a

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:advisor_name, :advisor_role, :advisor_nip, :sequence, :item_id]
      validate present(:advisor_name)
    end

    create :import do
      accept [:advisor_name, :advisor_role, :advisor_nip, :sequence, :item_id]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :advisor_name, :string, allow_nil?: false, public?: true

    attribute :advisor_role, :atom,
      constraints: [one_of: @advisor_roles],
      default: :main_advisor,
      public?: true

    attribute :advisor_nip, :string, public?: true
    attribute :sequence, :integer, default: 1, public?: true

    timestamps()
  end

  relationships do
    belongs_to :item, Kiroku.Repository.Item,
      allow_nil?: false,
      public?: true
  end
end
