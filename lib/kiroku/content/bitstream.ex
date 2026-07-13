defmodule Kiroku.Content.Bitstream do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @bundle_names ~w(ORIGINAL THUMBNAIL CHAPTER SUPPLEMENTAL ADMINISTRATIVE LICENSE MEDIA SOURCE)a
  @access_values ~w(open internal inherit restricted closed)a
  @storage_types ~w(url s3 local)a

  schema "bitstreams" do
    field :filename, :string
    field :bundle_name, Ecto.Enum, values: @bundle_names, default: :ORIGINAL
    field :sequence, :integer, default: 1
    field :description, :string
    field :mime_type, :string
    field :file_size, :integer
    field :checksum, :string
    field :checksum_algorithm, :string, default: "MD5"

    field :storage_type, Ecto.Enum, values: @storage_types, default: :local
    field :storage_url, :string
    field :storage_path, :string
    field :storage_bucket, :string

    field :access_level, Ecto.Enum, values: @access_values, default: :inherit
    field :embargo_open_date, :date
    field :embargo_close_date, :date

    # Denormalised last-fixity result (null = never checked).
    field :last_fixity_at, :utc_datetime_usec
    field :last_fixity_ok, :boolean

    belongs_to :item, Kiroku.Repository.Item

    timestamps()
  end

  def changeset(bitstream, attrs) do
    bitstream
    |> cast(attrs, [
      :filename,
      :bundle_name,
      :sequence,
      :description,
      :mime_type,
      :file_size,
      :checksum,
      :checksum_algorithm,
      :storage_type,
      :storage_url,
      :storage_path,
      :storage_bucket,
      :access_level,
      :embargo_open_date,
      :embargo_close_date,
      :item_id
    ])
    |> validate_required([:filename, :bundle_name, :sequence, :storage_type, :item_id])
    |> validate_length(:filename, min: 1, max: 500)
    |> enforce_bundle_access_rules()
    |> foreign_key_constraint(:item_id)
  end

  # Hard-coded access rules per plan Rule 4 and Rule 5.
  # These override whatever access_level was passed in attrs — they cannot be
  # changed via UI or import.
  defp enforce_bundle_access_rules(changeset) do
    case get_field(changeset, :bundle_name) do
      :THUMBNAIL ->
        put_change(changeset, :access_level, :open)

      bundle when bundle in [:ADMINISTRATIVE, :LICENSE] ->
        put_change(changeset, :access_level, :restricted)

      _ ->
        changeset
    end
  end
end
