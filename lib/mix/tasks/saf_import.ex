defmodule Mix.Tasks.Kiroku.Saf.Import do
  use Mix.Task

  @shortdoc "Import items from a DSpace Simple Archive Format archive"

  @moduledoc """
  Imports items from a DSpace Simple Archive Format directory or zip.

  ## Usage

      mix kiroku.saf.import --source=./export
      mix kiroku.saf.import --source=./col7.zip --collection=123456789/7
      mix kiroku.saf.import --source=./export --dry-run

  ## Options

    * `--source`       — directory or `.zip` path (required)
    * `--collection`   — owning collection handle or UUID; overrides per-item
                         `collections` files when present
    * `--dry-run`      — validate only, write nothing

  Re-importing an item whose `handle` file matches an existing item updates that
  item in place rather than creating a duplicate.

  The heavy lifting lives in `Kiroku.Saf.Importer`. The dashboard triggers the
  same logic via `Kiroku.Workers.SafImportWorker`.
  """

  alias Kiroku.Saf.Importer

  @requirements ["app.start"]

  def run(args) do
    opts = parse_opts(args)
    source = Keyword.get(opts, :source)

    if is_nil(source) do
      Mix.raise("Missing required option: --source")
    end

    unless File.exists?(source) do
      Mix.raise("Source not found: #{source}")
    end

    import_opts =
      []
      |> then(&if Keyword.get(opts, :dry_run), do: [{:dry_run, true} | &1], else: &1)
      |> then(fn list ->
        case Keyword.get(opts, :collection) do
          nil -> list
          c -> [{:collection, c} | list]
        end
      end)

    if Keyword.get(opts, :dry_run),
      do: Mix.shell().info("[DRY RUN] — no database writes will occur")

    case Importer.import_archive(source, import_opts) do
      {:ok, stats} ->
        Mix.shell().info("""

        Import complete.
          Processed : #{stats.processed}
          Inserted  : #{stats.inserted}
          Updated   : #{stats.updated}
          Skipped   : #{stats.skipped}
          Failed    : #{stats.failed}
        """)

        unless stats.errors == [] do
          Mix.shell().info("Errors:")

          Enum.each(stats.errors, fn e ->
            Mix.shell().info("  #{Path.basename(e.item_dir)}: #{inspect(e.reason)}")
          end)
        end

      {:error, :no_item_dirs} ->
        Mix.raise("No item_NNN/ directories found in #{source}")

      {:error, reason} ->
        Mix.raise("Import failed: #{inspect(reason)}")
    end
  end

  defp parse_opts(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [source: :string, collection: :string, dry_run: :boolean]
      )

    opts
  end
end
