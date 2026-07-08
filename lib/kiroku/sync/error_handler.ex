defmodule Kiroku.Sync.ErrorHandler do
  @moduledoc """
  Advanced error handling and recovery for sync operations.
  Implements intelligent retry logic, error categorization, and recovery mechanisms.
  """

  require Logger
  alias Kiroku.{Repo, Sync, Mailer}
  import Ecto.Query

  @error_categories [
    transient: [
      "connection refused",
      "timeout",
      "network",
      "temporary",
      "retry",
      "deadlock"
    ],
    data: [
      "validation",
      "constraint",
      "foreign key",
      "null constraint",
      "unique constraint"
    ],
    system: [
      "out of memory",
      "disk full",
      "permission denied",
      "configuration"
    ],
    critical: [
      "corruption",
      "data loss",
      "security",
      "authentication"
    ]
  ]

  @retry_configs %{
    transient: [max_attempts: 5, backoff: :exponential, initial_delay: 1_000],
    data: [max_attempts: 3, backoff: :linear, initial_delay: 5_000],
    system: [max_attempts: 2, backoff: :fixed, initial_delay: 10_000],
    critical: [max_attempts: 1, backoff: :none, initial_delay: 0]
  }

  @doc """
  Categorize an error based on its message and type.
  Returns :transient, :data, :system, or :critical
  """
  def categorize_error(error) when is_binary(error) do
    lower_error = String.downcase(error)

    Enum.find_value(@error_categories, :unknown, fn {category, patterns} ->
      if Enum.any?(patterns, &String.contains?(lower_error, &1)) do
        category
      end
    end)
  end

  def categorize_error(error) when is_exception(error) do
    categorize_error(Exception.message(error))
  end

  def categorize_error(_), do: :unknown

  @doc """
  Get retry configuration for an error category.
  """
  def get_retry_config(category) do
    Map.get(@retry_configs, category, @retry_configs.transient)
  end

  @doc """
  Determine if a record should be retried based on error category and attempt count.
  """
  def should_retry?(error, attempt_count) do
    category = categorize_error(error)
    config = get_retry_config(category)
    attempt_count < config.max_attempts
  end

  @doc """
  Calculate retry delay with backoff strategy.
  """
  def calculate_retry_delay(category, attempt) do
    config = get_retry_config(category)
    base_delay = config.initial_delay

    case config.backoff do
      :exponential ->
        trunc(base_delay * :math.pow(2, attempt - 1))

      :linear ->
        base_delay * attempt

      :fixed ->
        base_delay

      :none ->
        0
    end
  end

  @doc """
  Handle a failed sync record with intelligent retry logic.
  """
  def handle_failed_record(sync_run_id, legacy_id, error, attempt \\ 1) do
    category = categorize_error(error)

    Logger.warning(
      "Record sync failed (category: #{category}, attempt #{attempt}): #{inspect(error)}"
    )

    cond do
      should_retry?(error, attempt) ->
        # Schedule retry with appropriate delay
        schedule_retry(sync_run_id, legacy_id, error, attempt, category)
        {:retry, category}

      category in [:data, :critical] ->
        # Move to dead-letter queue for manual intervention
        move_to_dead_letter_queue(sync_run_id, legacy_id, error, category)
        notify_critical_failure(legacy_id, error, category)
        {:dead_letter, category}

      true ->
        # Log and move to failed status
        record_final_failure(sync_run_id, legacy_id, error, category)
        {:failed, category}
    end
  end

  @doc """
  Schedule a retry for a failed record.
  """
  def schedule_retry(sync_run_id, legacy_id, error, attempt, category) do
    delay = calculate_retry_delay(category, attempt)

    %{sync_run_id: sync_run_id, legacy_id: legacy_id, error: inspect(error), attempt: attempt}
    |> Kiroku.Workers.SyncRetryWorker.new(schedule_in: delay)
    |> Oban.insert()

    Logger.info("Scheduled retry for #{legacy_id} in #{delay}ms (attempt #{attempt})")
  end

  @doc """
  Move a record to the dead-letter queue.
  """
  def move_to_dead_letter_queue(sync_run_id, legacy_id, error, category) do
    # Check if already in dead-letter queue
    existing = Repo.get_by(Kiroku.Sync.DeadLetterQueue, legacy_id: legacy_id)

    if existing do
      # Update existing record
      existing
      |> Ecto.Changeset.change(%{
        error_message: inspect(error),
        retry_count: existing.retry_count + 1,
        last_attempted_at: DateTime.utc_now(),
        error_category: to_string(category)
      })
      |> Repo.update()
    else
      # Create new dead-letter record
      %Kiroku.Sync.DeadLetterQueue{}
      |> Ecto.Changeset.change(%{
        sync_run_id: sync_run_id,
        legacy_id: legacy_id,
        error_message: inspect(error),
        retry_count: 0,
        first_failed_at: DateTime.utc_now(),
        last_attempted_at: DateTime.utc_now(),
        error_category: to_string(category)
      })
      |> Repo.insert()
    end
  end

  @doc """
  Record a final failure for a record that won't be retried.
  """
  def record_final_failure(sync_run_id, legacy_id, error, _category) do
    # Update the sync record tracking
    case Sync.get_record_tracking(sync_run_id, legacy_id) do
      nil ->
        :ok

      tracking ->
        tracking
        |> Ecto.Changeset.change(%{
          action: "failed",
          error_message: inspect(error)
        })
        |> Repo.update()
    end

    Logger.error("Final failure recorded for #{legacy_id}: #{inspect(error)}")
  end

  @doc """
  Notify administrators about critical sync failures.
  """
  def notify_critical_failure(legacy_id, error, category) do
    # Get admin users
    admins = Kiroku.Accounts.list_admins()

    if Enum.any?(admins) do
      admins
      |> Enum.each(fn admin ->
        if admin.email do
          Swoosh.Email.new()
          |> Swoosh.Email.to({admin.display_name || admin.email, admin.email})
          |> Swoosh.Email.from({"Kiroku Sync", sync_mailer_from()})
          |> Swoosh.Email.subject("Critical Sync Failure: #{legacy_id}")
          |> Swoosh.Email.text_body("""
          A critical sync failure has occurred that requires manual intervention.

          Legacy ID: #{legacy_id}
          Error Category: #{category}
          Error: #{inspect(error)}

          This record has been moved to the dead-letter queue. Please review and take appropriate action.

          Admin Sync Dashboard: #{base_url()}/admin/sync
          """)
          |> Mailer.deliver()
        end
      end)
    end

    Logger.error("Critical sync failure notification sent for #{legacy_id}")
  end

  @doc """
  Notify about failed sync runs.
  """
  def notify_sync_run_failure(sync_run) do
    admins = Kiroku.Accounts.list_admins()

    if Enum.any?(admins) do
      admins
      |> Enum.each(fn admin ->
        if admin.email do
          Swoosh.Email.new()
          |> Swoosh.Email.to({admin.display_name || admin.email, admin.email})
          |> Swoosh.Email.from({"Kiroku Sync", sync_mailer_from()})
          |> Swoosh.Email.subject("Sync Run Failed: #{sync_run.source_view}")
          |> Swoosh.Email.text_body("""
          A sync run has failed for view: #{sync_run.source_view}

          Started: #{format_datetime(sync_run.started_at)}
          Records Processed: #{sync_run.records_processed}
          Records Failed: #{sync_run.records_failed}

          Error: #{sync_run.error_message}

          Please check the admin sync dashboard for more details.
          Admin Sync Dashboard: #{base_url()}/admin/sync
          """)
          |> Mailer.deliver()
        end
      end)
    end
  end

  @doc """
  Analyze error patterns and provide recommendations.
  """
  def analyze_error_patterns(limit \\ 100) do
    recent_failures =
      Repo.all(
        from t in Kiroku.Sync.SyncRecordTracking,
          where: t.action == "failed",
          order_by: [desc: t.inserted_at],
          limit: ^limit
      )

    error_categories =
      recent_failures
      |> Enum.group_by(fn tracking ->
        categorize_error(tracking.error_message || "unknown error")
      end)
      |> Enum.map(fn {category, failures} ->
        %{
          category: category,
          count: length(failures),
          sample_errors: Enum.take(failures, 3) |> Enum.map(& &1.error_message)
        }
      end)
      |> Enum.sort_by(& &1.count, :desc)

    %{
      total_failures: length(recent_failures),
      error_categories: error_categories,
      recommendations: generate_recommendations(error_categories)
    }
  end

  defp generate_recommendations(error_categories) do
    recommendations = []

    recommendations =
      if Enum.any?(error_categories, &(&1.category == :transient and &1.count > 10)) do
        ["Consider increasing retry attempts for transient errors" | recommendations]
      else
        recommendations
      end

    recommendations =
      if Enum.any?(error_categories, &(&1.category == :data and &1.count > 5)) do
        ["Review data validation rules and constraints" | recommendations]
      else
        recommendations
      end

    recommendations =
      if Enum.any?(error_categories, &(&1.category == :critical)) do
        ["Immediate attention required: critical errors detected" | recommendations]
      else
        recommendations
      end

    if Enum.empty?(recommendations) do
      ["No major issues detected - sync system is functioning normally"]
    else
      recommendations
    end
  end

  # Helper functions
  defp sync_mailer_from do
    domain = Application.get_env(:kiroku, :institution_domain, "kiroku.example.com")
    "no-reply@#{domain}"
  end

  defp base_url do
    host = Application.get_env(:kiroku, KirokuWeb.Endpoint)[:url][:host] || "localhost"
    "https://#{host}"
  end

  defp format_datetime(nil), do: "Unknown"

  defp format_datetime(%NaiveDateTime{} = dt) do
    dt
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.shift_zone!("Asia/Jakarta")
    |> Calendar.strftime("%Y-%m-%d %H:%M:%S")
  end

  defp format_datetime(%DateTime{} = dt) do
    dt
    |> DateTime.shift_zone!("Asia/Jakarta")
    |> Calendar.strftime("%Y-%m-%d %H:%M:%S")
  end
end
