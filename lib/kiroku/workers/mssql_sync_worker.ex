defmodule Kiroku.Workers.MssqlSyncWorker do
  @moduledoc """
  Background worker for incremental MSSQL synchronization.

  Enqueued by:
    - the Oban cron schedule in `config/config.exs` (every 6h per view)
    - the manual "Sync <View>" buttons on `/admin/sync`

  Processes only changed records from the legacy view and updates PostgreSQL.
  The record-processing logic lives in `Kiroku.Sync.Importer`.
  """

  use Oban.Worker, queue: :sync, max_attempts: 3, unique: [period: 300]

  require Logger

  alias Kiroku.{LegacyRepo, Sync}
  alias Kiroku.Sync.Importer

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    view_name = args["view"]
    triggered_by = args["triggered_by"]

    Logger.info("[MssqlSyncWorker] starting incremental sync for view: #{view_name}")

    case ensure_legacy_repo() do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error("[MssqlSyncWorker] cannot start LegacyRepo: #{inspect(reason)}")
        {:error, "Failed to start LegacyRepo: #{inspect(reason)}"}
    end

    metadata = %{
      "run_type" => "sync",
      "trigger" => if(triggered_by, do: "manual", else: "cron"),
      "triggered_by" => triggered_by
    }

    {:ok, sync_run} = Sync.start_sync_run(view_name, metadata)

    try do
      stats =
        Importer.run_view(view_name,
          incremental: true,
          sync_run: sync_run,
          log: true
        )

      complete_or_fail(sync_run, stats)

      Logger.info(
        "[MssqlSyncWorker] #{view_name} done — processed=#{stats.processed} " <>
          "inserted=#{stats.inserted} updated=#{stats.updated} failed=#{stats.failed}"
      )

      :ok
    rescue
      error ->
        Logger.error("[MssqlSyncWorker] #{view_name} failed: #{inspect(error)}")
        Sync.fail_sync_run(sync_run, inspect(error))
        {:error, inspect(error)}
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
