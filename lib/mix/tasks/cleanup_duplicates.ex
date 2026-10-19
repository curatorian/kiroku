defmodule Mix.Tasks.Kiroku.CleanupDuplicates do
  @moduledoc """
  Removes duplicate bitstreams and sync_record_tracking entries.

  ## Usage

      mix kiroku.cleanup_duplicates

  Dry-run (preview only):

      mix kiroku.cleanup_duplicates --dry-run
  """

  use Mix.Task

  import Ecto.Query

  @shortdoc "Clean up duplicate bitstreams and tracking records"

  def run(args) do
    Mix.Task.run("app.start")

    dry_run? = "--dry-run" in args

    if dry_run? do
      IO.puts(IO.ANSI.yellow() <> "DRY RUN — no changes will be made" <> IO.ANSI.reset())
    end

    IO.puts("")
    clean_bitstreams(dry_run?)
    IO.puts("")
    clean_tracking(dry_run?)

    IO.puts("\n" <> IO.ANSI.green() <> "Done." <> IO.ANSI.reset())
  end

  defp clean_bitstreams(dry_run?) do
    IO.puts(IO.ANSI.format([:bright, "Bitstream duplicates"]))

    # Count duplicates: same (item_id, filename) > 1 row
    duplicate_groups =
      Kiroku.Repo.all(
        from b in "bitstreams",
          group_by: [b.item_id, b.filename],
          having: count(b.id) > 1,
          select: {b.item_id, b.filename, count(b.id)}
      )

    total_dupes =
      Enum.reduce(duplicate_groups, 0, fn {_item_id, _filename, count}, acc -> acc + count end)

    IO.puts("  Duplicate groups: #{length(duplicate_groups)}")
    IO.puts("  Total rows to remove: #{total_dupes - length(duplicate_groups)}")

    unless dry_run? or duplicate_groups == [] do
      {time_us, _} =
        :timer.tc(fn ->
          Enum.each(duplicate_groups, fn {item_id, filename, _count} ->
            # Keep the newest row (highest inserted_at), delete the rest
            keep =
              Kiroku.Repo.one!(
                from b in "bitstreams",
                  where: b.item_id == ^item_id and b.filename == ^filename,
                  order_by: [desc: b.inserted_at],
                  limit: 1,
                  select: b.id
              )

            {_deleted, _} =
              Kiroku.Repo.delete_all(
                from b in "bitstreams",
                  where: b.item_id == ^item_id and b.filename == ^filename and b.id != ^keep
              )
          end)
        end)

      IO.puts("\n  Removed in #{Float.round(time_us / 1_000_000, 1)}s")
    end
  end

  defp clean_tracking(dry_run?) do
    IO.puts(IO.ANSI.format([:bright, "Sync record tracking duplicates"]))

    dup_ids =
      Kiroku.Repo.all(
        from t in "sync_record_tracking",
          group_by: t.legacy_id,
          having: count(t.id) > 1,
          select: t.legacy_id
      )

    dup_count = length(dup_ids)

    IO.puts("  Duplicate legacy_ids: #{dup_count}")

    unless dry_run? or dup_count == 0 do
      # For each legacy_id with multiple rows, keep the newest and delete the rest
      {time_us, _} =
        :timer.tc(fn ->
          Kiroku.Repo.transaction(fn ->
            # Get all legacy_ids that have duplicates
            dup_ids =
              Kiroku.Repo.all(
                from t in "sync_record_tracking",
                  group_by: t.legacy_id,
                  having: count(t.id) > 1,
                  select: t.legacy_id
              )

            Enum.each(dup_ids, fn legacy_id ->
              keep =
                Kiroku.Repo.one!(
                  from t in "sync_record_tracking",
                    where: t.legacy_id == ^legacy_id,
                    order_by: [desc: t.synced_at],
                    limit: 1,
                    select: t.id
                )

              {_deleted, _} =
                Kiroku.Repo.delete_all(
                  from t in "sync_record_tracking",
                    where: t.legacy_id == ^legacy_id and t.id != ^keep
                )
            end)
          end)
        end)

      IO.puts("\n  Removed in #{Float.round(time_us / 1_000_000, 1)}s")
    end
  end
end
