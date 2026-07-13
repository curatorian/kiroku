defmodule Kiroku.Repo.Migrations.AddAccessLevelToCommunitiesAndCollections do
  use Ecto.Migration

  # access_level columns are plain strings (not native PG enums), matching the
  # existing items.access_level / bitstreams.access_level convention. This means
  # the new "internal" value needs no value-list migration — only these new
  # columns are introduced. Existing rows backfill to "open".
  def change do
    alter table(:communities) do
      add :access_level, :string, null: false, default: "open"
    end

    alter table(:collections) do
      add :access_level, :string, null: false, default: "open"
      add :default_item_access_level, :string, null: false, default: "open"
    end

    create index(:communities, [:access_level])
    create index(:collections, [:access_level])
  end
end
