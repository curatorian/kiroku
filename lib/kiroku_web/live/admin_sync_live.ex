defmodule KirokuWeb.AdminSyncLive do
  use KirokuWeb, :live_view

  alias Kiroku.{Sync, Repo}
  alias Kiroku.Sync.DeadLetterQueue
  import Ecto.Query

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign_sync_stats(socket)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, params)}
  end

  defp apply_action(socket, %{"id" => id}) do
    socket
    |> assign(:page_title, "Sync Run Details")
    |> assign(:sync_run, Sync.get_sync_run!(id))
  end

  defp apply_action(socket, _params) do
    socket
    |> assign(:page_title, "MSSQL Synchronization")
    |> assign(:sync_run, nil)
  end

  @impl true
  def handle_event("refresh", _, socket) do
    {:noreply, assign_sync_stats(socket)}
  end

  def handle_event("trigger_sync", %{"view" => view}, socket) do
    # Enqueue a manual sync job
    %{view: view}
    |> Kiroku.Workers.MssqlSyncWorker.new()
    |> Oban.insert()

    {:noreply, put_flash(socket, :info, "Sync job queued for #{view}")}
  end

  def handle_event("retry_dead_letter", %{"id" => id}, socket) do
    # Retry a specific dead letter record
    dead_letter = Repo.get!(DeadLetterQueue, id)

    # Schedule retry
    Sync.ErrorHandler.schedule_retry(
      dead_letter.sync_run_id,
      dead_letter.legacy_id,
      dead_letter.error_message,
      dead_letter.retry_count + 1,
      String.to_existing_atom(dead_letter.error_category)
    )

    {:noreply, put_flash(socket, :info, "Retry job scheduled for #{dead_letter.legacy_id}")}
  end

  def handle_event("resolve_dead_letter", %{"id" => id, "resolution_notes" => notes}, socket) do
    # Mark a dead letter record as resolved manually
    dead_letter = Repo.get!(DeadLetterQueue, id)

    dead_letter
    |> Ecto.Changeset.change(%{
      resolved_at: DateTime.utc_now(),
      resolution_notes: notes
    })
    |> Repo.update()

    {:noreply,
     put_flash(socket, :info, "Record marked as resolved")
     |> assign_sync_stats()}
  end

  defp assign_sync_stats(socket) do
    stats = Sync.get_sync_stats()
    recent_runs = Sync.list_sync_runs(limit: 10)
    failed_records = get_recent_failed_records(recent_runs)
    dead_letter_queue = get_dead_letter_queue()

    assign(socket, %{
      sync_stats: stats,
      recent_runs: recent_runs,
      failed_records: failed_records,
      dead_letter_queue: dead_letter_queue
    })
  end

  defp get_recent_failed_records(sync_runs) do
    sync_runs
    |> Enum.filter(&(&1.status == "failed" or &1.records_failed > 0))
    |> Enum.flat_map(fn run ->
      Sync.list_failed_records(run.id, limit: 5)
    end)
    |> Enum.take(20)
  end

  def get_dead_letter_queue(limit \\ 50) do
    Repo.all(
      from d in DeadLetterQueue,
        where: is_nil(d.resolved_at),
        order_by: [desc: d.first_failed_at],
        limit: ^limit
    )
  end

  def format_datetime(nil), do: "Never"

  def format_datetime(dt) do
    dt
    |> DateTime.shift_zone!("Asia/Jakarta")
    |> Calendar.strftime("%Y-%m-%d %H:%M:%S")
  end

  def sync_status_badge("pending"), do: "bg-yellow-100 text-yellow-800"
  def sync_status_badge("running"), do: "bg-blue-100 text-blue-800"
  def sync_status_badge("completed"), do: "bg-green-100 text-green-800"
  def sync_status_badge("failed"), do: "bg-red-100 text-red-800"
  def sync_status_badge(_), do: "bg-gray-100 text-gray-800"

  def error_category_badge("transient"), do: "bg-yellow-100 text-yellow-800"
  def error_category_badge("data"), do: "bg-orange-100 text-orange-800"
  def error_category_badge("system"), do: "bg-purple-100 text-purple-800"
  def error_category_badge("critical"), do: "bg-red-100 text-red-800"
  def error_category_badge(_), do: "bg-gray-100 text-gray-800"

  def format_duration(started, completed) do
    diff = DateTime.diff(completed, started)
    minutes = div(diff, 60)
    seconds = rem(diff, 60)

    cond do
      minutes > 0 -> "#{minutes}m #{seconds}s"
      true -> "#{seconds}s"
    end
  end
end
