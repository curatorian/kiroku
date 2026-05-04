defmodule Kiroku.Repo.Migrations.CreateBitstreams do
  use Ecto.Migration

  def change do
    create table(:bitstreams, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :filename, :string, null: false
      add :bundle_name, :string, null: false, default: "ORIGINAL"
      add :sequence, :integer, null: false, default: 1
      add :description, :string
      add :mime_type, :string
      add :file_size, :bigint
      add :checksum, :string
      add :checksum_algorithm, :string, default: "MD5"

      add :storage_type, :string, null: false, default: "local"
      add :storage_url, :string
      add :storage_path, :string
      add :storage_bucket, :string

      add :access_level, :string, null: false, default: "inherit"
      add :embargo_open_date, :date
      add :embargo_close_date, :date

      add :item_id, references(:items, type: :binary_id, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:bitstreams, [:item_id])
    create index(:bitstreams, [:bundle_name])
    create index(:bitstreams, [:item_id, :bundle_name, :sequence])
  end
end
