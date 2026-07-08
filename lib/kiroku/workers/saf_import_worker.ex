defmodule Kiroku.Workers.SafImportWorker do
  @moduledoc """
  Imports items from a DSpace Simple Archive Format zip.

  Enqueued by the `/admin/saf` dashboard after a zip is uploaded. The source
  zip is staged in the OS temp directory (`/tmp`) by the LiveView and is
  **always** deleted after processing (success or failure, dry-run or real).

  Args:

    * `"source"`       — filesystem path to the uploaded `.zip` (in `/tmp`)
    * `"collection"`   — optional owning collection handle/UUID (overrides file)
    * `"dry_run"`      — when true, validate without persisting
    * `"triggered_by"` — user id of the admin who triggered the run
  """

  use Oban.Worker, queue: :sync, max_attempts: 1

  require Logger

  alias Kiroku.Saf.Importer

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    source = args["source"]

    result = do_import(source, args)

    # Always clean up the staged zip from /tmp, regardless of outcome.
    File.rm(source)

    result
  end

  defp do_import(source, args) do
    opts =
      []
      |> then(&if args["dry_run"], do: [{:dry_run, true} | &1], else: &1)
      |> then(fn list ->
        case args["collection"] do
          nil -> list
          c -> [{:collection, c} | list]
        end
      end)

    case Importer.import_archive(source, opts) do
      {:ok, stats} ->
        Logger.info(
          "[SafImportWorker] done — processed=#{stats.processed} " <>
            "inserted=#{stats.inserted} updated=#{stats.updated} failed=#{stats.failed}"
        )

        :ok

      {:error, :no_item_dirs} ->
        Logger.error("[SafImportWorker] no item_NNN/ dirs in #{source}")
        {:error, "no item directories found in archive"}

      {:error, reason} ->
        Logger.error("[SafImportWorker] failed: #{inspect(reason)}")
        {:error, inspect(reason)}
    end
  end
end
