defmodule Kiroku.Repo.Migrations.CreateItemAuthors do
  use Ecto.Migration

  def change do
    create table(:item_authors, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :author_name, :string, null: false
      add :author_name_alt, :string
      add :affiliation, :string
      add :email, :string
      add :orcid, :string
      add :scopus_author_id, :string
      add :sequence, :integer, default: 1
      add :item_id, references(:items, type: :binary_id, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:item_authors, [:item_id])
  end
end
