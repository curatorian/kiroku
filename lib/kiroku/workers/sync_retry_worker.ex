defmodule Kiroku.Workers.SyncRetryWorker do
  @moduledoc """
  Retries failed sync records from the dead-letter queue.

  Enqueued by `Kiroku.Sync.ErrorHandler.schedule_retry/5` with exponential
  backoff. The record-processing logic lives in `Kiroku.Sync.Importer`.
  """

  use Oban.Worker, queue: :sync_retries, max_attempts: 5, unique: [period: 60]

  require Logger

  alias Kiroku.{LegacyRepo, Repo}
  alias Kiroku.Sync.{DeadLetterQueue, ErrorHandler, Importer}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"legacy_id" => legacy_id} = args}) do
    attempt = Map.get(args, "attempt", 1)

    Logger.info("[SyncRetryWorker] retrying legacy_id=#{legacy_id} (attempt #{attempt})")

    case ensure_legacy_repo() do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error("[SyncRetryWorker] cannot start LegacyRepo: #{inspect(reason)}")
        {:error, "Failed to start LegacyRepo: #{inspect(reason)}"}
    end

    dead_letter = Repo.get_by(DeadLetterQueue, legacy_id: legacy_id)

    if dead_letter do
      retry_record(dead_letter, attempt)
    else
      Logger.warning(
        "[SyncRetryWorker] no dead-letter entry for #{legacy_id}, attempting direct retry"
      )

      retry_direct(legacy_id)
    end
  end

  defp retry_record(dead_letter, attempt) do
    {view_name, npm} = Importer.parse_legacy_id(dead_letter.legacy_id)

    if is_nil(view_name) do
      reason = "unrecognized legacy_id prefix: #{dead_letter.legacy_id}"
      Logger.error("[SyncRetryWorker] #{reason}")
      handle_failure(dead_letter, reason, attempt)
    else
      # Re-import the record without attaching tracking: the original run
      # already has a tracking row (and there's a unique constraint on
      # [:legacy_id, :sync_run_id]). The dead-letter entry records the retry
      # outcome via resolved_at / resolution_notes.
      case Importer.run_single(view_name, npm, sync_run: nil) do
        {:ok, action} ->
          mark_resolved(dead_letter, attempt, action)
          Logger.info("[SyncRetryWorker] resolved #{dead_letter.legacy_id} (#{action})")
          :ok

        {:error, :not_found} ->
          reason = "record not found in source view #{view_name}"
          Logger.error("[SyncRetryWorker] #{reason}")
          handle_failure(dead_letter, reason, attempt)

        {:error, reason} ->
          handle_failure(dead_letter, reason, attempt)
      end
    end
  end

  defp retry_direct(legacy_id) do
    {view_name, npm} = Importer.parse_legacy_id(legacy_id)

    cond do
      is_nil(view_name) ->
        {:error, "unrecognized legacy_id prefix: #{legacy_id}"}

      true ->
        case Importer.run_single(view_name, npm) do
          {:ok, action} ->
            Logger.info("[SyncRetryWorker] direct retry succeeded for #{legacy_id} (#{action})")
            :ok

          {:error, reason} ->
            Logger.error(
              "[SyncRetryWorker] direct retry failed for #{legacy_id}: #{inspect(reason)}"
            )

            {:error, inspect(reason)}
        end
    end
  end

  defp mark_resolved(dead_letter, attempt, action) do
    dead_letter
    |> Ecto.Changeset.change(%{
      resolved_at: DateTime.utc_now(),
      resolution_notes: "Successfully synced on attempt #{attempt} (#{action})",
      retry_count: attempt
    })
    |> Repo.update!()
  end

  defp handle_failure(dead_letter, reason, attempt) do
    dead_letter
    |> Ecto.Changeset.change(%{
      retry_count: attempt,
      last_attempted_at: DateTime.utc_now(),
      error_message: inspect(reason)
    })
    |> Repo.update()

    ErrorHandler.handle_failed_record(
      dead_letter.sync_run_id,
      dead_letter.legacy_id,
      reason,
      attempt + 1
    )
  end

  defp ensure_legacy_repo do
    case LegacyRepo.start_link() do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
