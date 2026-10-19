defmodule Mix.Tasks.Kiroku.ResetEmptyTitles do
  @moduledoc """
  Resets sync tracking for items with "Empty Title" or null abstract
  so the next incremental sync re-fetches them from MSSQL.

  ## Usage

      mix kiroku.reset_empty_titles

  Dry-run:

      mix kiroku.reset_empty_titles --dry-run
  """

  use Mix.Task

  import Ecto.Query

  alias Kiroku.Repo
  alias Kiroku.Repository.Item

  @shortdoc "Reset sync tracking for empty title items"

  def run(args) do
    Mix.Task.run("app.start")
    dry_run? = "--dry-run" in args

    if dry_run? do
      IO.puts(IO.ANSI.format([:bright, "DRY RUN — no changes will be made"]))
    end

    item_ids =
      Repo.all(
        from i in Item,
          where: i.title == "Empty Title" or is_nil(i.abstract),
          select: i.id
      )

    item_uuids = Enum.map(item_ids, &Ecto.UUID.dump!/1)

    IO.puts("\nFound #{length(item_uuids)} items with empty title or null abstract")

    if item_uuids == [] do
      IO.puts("Nothing to do.")
    else
      unless dry_run? do
        {deleted, _} =
          Repo.delete_all(
            from t in "sync_record_tracking",
              where: t.item_id in ^item_uuids
          )

        IO.puts("Deleted #{deleted} sync_record_tracking entries")
      end

      IO.puts("\nNext sync will re-fetch these records from MSSQL.")
    end
  end
end
