defmodule Kiroku.Workers.ImportWorker do
  @moduledoc """
  Background worker for full MSSQL imports triggered from the dashboard.

  Unlike `Kiroku.Workers.MssqlSyncWorker` (incremental, change-aware), this
  worker re-processes every record in the view — equivalent to running
  `mix kiroku.import_from_mssql --view <View>`.

  Enqueued by the `/admin/sync` page. Args:

    * `"view"`    — view name, or `"all"` for every view
    * `"dry_run"` — when true, parse/validate but persist nothing
    * `"triggered_by"` — the user id of the admin who triggered the run

  The record-processing logic lives in `Kiroku.Sync.Importer`.
  """

  use Oban.Worker, queue: :sync, max_attempts: 1, unique: [period: 600]

  require Logger

  alias Kiroku.{LegacyRepo, Sync}
  alias Kiroku.Sync.Importer

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    view_arg = args["view"] || "all"
    dry_run? = Map.get(args, "dry_run", false)
    triggered_by = args["triggered_by"]

    views =
      case view_arg do
        "all" -> Importer.views()
        name -> Enum.filter(Importer.views(), fn {v, _} -> v == name end)
      end

    if views == [] do
      Logger.error("[ImportWorker] no matching view for #{inspect(view_arg)}")
      {:error, "invalid view: #{inspect(view_arg)}"}
    else
      case ensure_legacy_repo() do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.error("[ImportWorker] cannot start LegacyRepo: #{inspect(reason)}")
          {:error, "Failed to start LegacyRepo: #{inspect(reason)}"}
      end

      mode = if dry_run?, do: "dry-run import", else: "full import"

      Logger.info(
        "[ImportWorker] starting #{mode} for #{length(views)} view(s), " <>
          "triggered_by=#{triggered_by || "unknown"}"
      )

      results =
        Enum.map(views, fn {view_name, _} ->
          run_one_view(view_name, dry_run?, triggered_by)
        end)

      # Fail the job only if every view failed; partial failures are surfaced
      # via the per-view SyncRun records on the dashboard.
      all_failed? = Enum.all?(results, &(&1 == :error))

      if all_failed? do
        {:error, "all views failed"}
      else
        :ok
      end
    end
  end

  defp run_one_view(view_name, dry_run?, triggered_by) do
    metadata = %{
      "run_type" => if(dry_run?, do: "import_dry_run", else: "import"),
      "trigger" => "dashboard",
      "triggered_by" => triggered_by
    }

    sync_run =
      if dry_run? do
        nil
      else
        {:ok, run} = Sync.start_sync_run(view_name, metadata)
        run
      end

    try do
      stats =
        Importer.run_view(view_name,
          dry_run: dry_run?,
          incremental: false,
          sync_run: sync_run,
          log: true
        )

      if sync_run do
        complete_or_fail(sync_run, stats)
      end

      Logger.info(
        "[ImportWorker] #{view_name} done — processed=#{stats.processed} " <>
          "inserted=#{stats.inserted} updated=#{stats.updated} failed=#{stats.failed}"
      )

      :ok
    rescue
      error ->
        Logger.error("[ImportWorker] #{view_name} failed: #{inspect(error)}")

        if sync_run do
          Sync.fail_sync_run(sync_run, inspect(error))
        end

        :error
    end
  end

  defp ensure_legacy_repo do
    case LegacyRepo.start_link() do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp complete_or_fail(sync_run, %{failed: failed, total: total})
       when failed > 0 and total > 0 and failed >= total do
    Sync.fail_sync_run(sync_run, "all #{failed} records failed")
  end

  defp complete_or_fail(sync_run, stats) do
    Sync.complete_sync_run(sync_run, %{
      processed: stats.processed,
      inserted: stats.inserted,
      updated: stats.updated,
      failed: stats.failed,
      last_synced_at: DateTime.utc_now(),
      last_synced_legacy_id: Importer.last_legacy_id(sync_run.source_view)
    })
  end
end
