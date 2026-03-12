defmodule Kiroku.Content.Bitstream do
  use Ash.Resource,
    otp_app: :kiroku,
    domain: Kiroku.Content,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "bitstreams"
    repo Kiroku.Repo

    custom_indexes do
      index [:bundle_name]
      index [:item_id]
    end
  end

  @bundle_names ~w(ORIGINAL THUMBNAIL CHAPTER SUPPLEMENTAL ADMINISTRATIVE LICENSE MEDIA SOURCE)a
  @storage_types ~w(url s3 local)a
  @access_levels ~w(inherit open restricted closed)a

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :filename,
        :bundle_name,
        :sequence,
        :description,
        :storage_type,
        :storage_url,
        :storage_path,
        :storage_bucket,
        :mime_type,
        :size_bytes,
        :checksum,
        :checksum_algorithm,
        :access_level,
        :embargo_open_date,
        :embargo_close_date,
        :item_id
      ]
    end

    create :import do
      accept [
        :filename,
        :bundle_name,
        :sequence,
        :description,
        :storage_type,
        :storage_url,
        :storage_path,
        :storage_bucket,
        :mime_type,
        :size_bytes,
        :checksum,
        :checksum_algorithm,
        :access_level,
        :embargo_open_date,
        :embargo_close_date,
        :item_id
      ]
    end

    update :update do
      accept [:access_level, :embargo_open_date, :embargo_close_date, :description]
      require_atomic? false
    end

    update :lift_embargo do
      require_atomic? false
      change set_attribute(:embargo_open_date, nil)
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type([:create, :update]) do
      authorize_if actor_attribute_equals(:user_type, :admin)
      authorize_if actor_attribute_equals(:user_type, :superadmin)
      authorize_if actor_attribute_equals(:user_type, :submitter)
    end

    policy action(:import) do
      authorize_if always()
    end

    policy action_type(:destroy) do
      authorize_if actor_attribute_equals(:user_type, :admin)
      authorize_if actor_attribute_equals(:user_type, :superadmin)
    end
  end

  validations do
    validate Kiroku.Content.Bitstream.Validations.StorageFields
  end

  attributes do
    uuid_primary_key :id

    attribute :filename, :string, allow_nil?: false, public?: true

    attribute :bundle_name, :atom,
      constraints: [one_of: @bundle_names],
      default: :ORIGINAL,
      public?: true

    attribute :sequence, :integer, default: 0, public?: true
    attribute :description, :string, public?: true

    attribute :storage_type, :atom,
      constraints: [one_of: @storage_types],
      default: :url,
      public?: true

    attribute :storage_url, :string, public?: true
    attribute :storage_path, :string, public?: true
    attribute :storage_bucket, :string, public?: true

    attribute :mime_type, :string, public?: true
    attribute :size_bytes, :integer, default: 0, public?: true
    attribute :checksum, :string, public?: true
    attribute :checksum_algorithm, :string, default: "md5", public?: true

    attribute :access_level, :atom,
      constraints: [one_of: @access_levels],
      default: :inherit,
      public?: true

    attribute :embargo_open_date, :date, public?: true
    attribute :embargo_close_date, :date, public?: true

    timestamps()
  end

  relationships do
    belongs_to :item, Kiroku.Repository.Item,
      allow_nil?: false,
      public?: true
  end
end
