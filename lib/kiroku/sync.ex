defmodule Kiroku.Sync do
  @moduledoc """
  Context module for managing MSSQL synchronization operations.
  Handles sync run tracking, change detection, and sync status monitoring.

  The entire feature is **optional**. Call `enabled?/0` to check whether
  MSSQL is configured before invoking any sync functions.
  """

  import Ecto.Query
  alias Kiroku.Repo
  alias Kiroku.Sync.{SyncRun, SyncRecordTracking}

  @doc """
  Returns `true` when the MSSQL legacy import source is configured.

  Checks for the `MSSQL_HOST` environment variable. When this returns `false`,
  all sync/import operations are no-ops and the UI hides sync-related widgets.
  """
  def enabled? do
    System.get_env("MSSQL_HOST") not in [nil, ""]
  end

  # ── Sync Run Management ─────────────────────────────────────────────────────

  def list_sync_runs(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)
    status = Keyword.get(opts, :status)
    source_view = Keyword.get(opts, :source_view)

    query = from(s in SyncRun, order_by: [desc: s.started_at])

    query =
      if status do
        from(s in query, where: s.status == ^status)
      else
        query
      end

    query =
      if source_view do
        from(s in query, where: s.source_view == ^source_view)
      else
        query
      end

    query
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
    |> Repo.preload(:sync_record_tracking)
  end

  def get_sync_run!(id), do: Repo.get!(SyncRun, id)

  def get_latest_sync_run(source_view) do
    Repo.one(
      from s in SyncRun,
        where: s.source_view == ^source_view,
        order_by: [desc: s.started_at],
        limit: 1
    )
  end

  def create_sync_run(attrs) do
    %SyncRun{}
    |> SyncRun.changeset(attrs)
    |> Repo.insert()
  end

  def update_sync_run(%SyncRun{} = sync_run, attrs) do
    sync_run
    |> SyncRun.changeset(attrs)
    |> Repo.update()
  end

  def start_sync_run(source_view, metadata \\ %{}) do
    create_sync_run(%{
      source_view: source_view,
      status: "running",
      started_at: DateTime.utc_now(),
      metadata: metadata
    })
  end

  def complete_sync_run(%SyncRun{} = sync_run, stats) do
    update_sync_run(sync_run, %{
      status: "completed",
      completed_at: DateTime.utc_now(),
      records_processed: Map.get(stats, :processed, 0),
      records_inserted: Map.get(stats, :inserted, 0),
      records_updated: Map.get(stats, :updated, 0),
      records_failed: Map.get(stats, :failed, 0),
      last_synced_at: Map.get(stats, :last_synced_at),
      last_synced_legacy_id: Map.get(stats, :last_synced_legacy_id)
    })
  end

  def fail_sync_run(%SyncRun{} = sync_run, error_message) do
    update_sync_run(sync_run, %{
      status: "failed",
      completed_at: DateTime.utc_now(),
      error_message: error_message
    })
  end

  def get_sync_stats do
    query = """
    SELECT 
      source_view,
      COUNT(*) as total_runs,
      COUNT(CASE WHEN status = 'completed' THEN 1 END) as completed_runs,
      COUNT(CASE WHEN status = 'failed' THEN 1 END) as failed_runs,
      MAX(started_at) as last_run_at,
      SUM(records_processed) as total_records_processed,
      SUM(records_inserted) as total_records_inserted,
      SUM(records_updated) as total_records_updated,
      SUM(records_failed) as total_records_failed
    FROM sync_runs
    GROUP BY source_view
    """

    case Repo.query(query) do
      {:ok, %{rows: rows, columns: columns}} ->
        rows
        |> Enum.map(fn row ->
          Enum.zip(columns, row)
          |> Map.new()
        end)

      {:error, _reason} ->
        []
    end
  end

  # ── Sync Record Tracking ────────────────────────────────────────────────────

  def create_record_tracking(attrs) do
    %SyncRecordTracking{}
    |> SyncRecordTracking.changeset(attrs)
    |> Repo.insert()
  end

  def get_record_tracking(sync_run_id, legacy_id) do
    Repo.get_by(SyncRecordTracking, sync_run_id: sync_run_id, legacy_id: legacy_id)
  end

  def get_latest_record_tracking(legacy_id) do
    Repo.one(
      from t in SyncRecordTracking,
        where: t.legacy_id == ^legacy_id,
        order_by: [desc: t.synced_at],
        limit: 1
    )
  end

  def list_failed_records(sync_run_id, limit \\ 100) do
    Repo.all(
      from t in SyncRecordTracking,
        where: t.sync_run_id == ^sync_run_id and t.action == "failed",
        limit: ^limit
    )
  end

  @doc """
  Returns failed records across multiple sync runs in a single query.
  """
  def list_failed_records_for_runs(sync_run_ids, limit \\ 20) do
    Repo.all(
      from t in SyncRecordTracking,
        where: t.sync_run_id in ^sync_run_ids and t.action == "failed",
        order_by: [desc: t.synced_at],
        limit: ^limit
    )
  end

  @doc """
  Returns the latest sync run for each of the given source views in a single
  query (avoids N+1).
  """
  def get_latest_sync_runs(source_views) do
    import Ecto.Query

    from(s in SyncRun,
      where: s.source_view in ^source_views,
      order_by: [s.source_view, desc: s.started_at]
    )
    |> distinct([s], s.source_view)
    |> Repo.all()
  end

  def calculate_record_checksum(record) do
    # Create a checksum for the record to detect changes. Records are
    # `Kiroku.LegacyView` structs (atom keys); field/2 tolerates string keys too.
    relevant_fields = [
      field(record, :Judul),
      field(record, :Abstrak),
      field(record, :Fakultas),
      field(record, :Program_Studi),
      field(record, :Jenjang),
      field(record, :Nama),
      field(record, :stPublikasi),
      field(record, :Verifikasi),
      field(record, :Validasi),
      field(record, :LinkPath),
      field(record, :FileCover),
      field(record, :FileAbstrak),
      field(record, :Tgl_Upload)
    ]

    relevant_fields
    |> Enum.map(fn
      nil -> ""
      val -> to_string(val)
    end)
    |> Enum.join("|")
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  def record_changed?(legacy_id, new_checksum) do
    case get_latest_record_tracking(legacy_id) do
      # No previous record, so it's new
      nil -> true
      tracking -> tracking.checksum != new_checksum
    end
  end

  # ── Change Detection ─────────────────────────────────────────────────────────

  def get_sync_position(source_view) do
    case get_latest_sync_run(source_view) do
      nil ->
        # First sync - return epoch
        %{
          last_synced_at: ~U[1970-01-01 00:00:00Z],
          last_synced_legacy_id: nil
        }

      sync_run ->
        %{
          last_synced_at: sync_run.last_synced_at || sync_run.started_at,
          last_synced_legacy_id: sync_run.last_synced_legacy_id
        }
    end
  end

  def should_sync_record?(record, source_view) do
    # For incremental sync, check if record has changed since last sync
    position = get_sync_position(source_view)
    checksum = calculate_record_checksum(record)
    legacy_id = build_legacy_id(field(record, :Jenis), field(record, :NPM))

    # Check if record is new or changed
    new_record? = is_nil(get_latest_record_tracking(legacy_id))
    changed_record? = record_changed?(legacy_id, checksum)

    upload_after_sync? =
      case {field(record, :Tgl_Upload), position.last_synced_at} do
        {nil, _} -> true
        {_, nil} -> true
        {tgl, last} -> DateTime.compare(tgl, last) == :gt
      end

    new_record? or changed_record? or upload_after_sync?
  end

  defp build_legacy_id(nil, npm), do: "unknown/#{npm}"
  defp build_legacy_id("", npm), do: "unknown/#{npm}"

  defp build_legacy_id(jenis, npm) do
    slug = (jenis || "unknown") |> String.downcase() |> String.replace(" ", "-")
    "#{slug}/#{npm}"
  end

  # Key-agnostic field accessor. Records arrive as `Kiroku.LegacyView` structs
  # (atom keys from Ecto); string keys tolerated defensively.
  defp field(record, key) when is_atom(key) do
    Map.get(record, key) || Map.get(record, Atom.to_string(key))
  end
end
