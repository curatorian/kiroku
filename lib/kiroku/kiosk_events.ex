defmodule Kiroku.KioskEvents do
  @moduledoc """
  Visitor events reported by kiosks (SPEC 7.6). Kiosks buffer events locally
  and flush them as a batch; insertion is idempotent per
  (session_id, type, occurred_at) so a replayed buffer never duplicates rows.
  """

  import Ecto.Query

  alias Kiroku.{KioskEvent, Repo}

  @max_batch_size 500

  @doc """
  Records a batch of events: `%{ "session_id" => ..., "type" => ..., "timestamp" => ..., "payload" => ... }[]`.

  Accepts both `occurred_at` and `timestamp` keys for the event time (ISO8601
  or DateTime), and `sessionId`/`event_type` camelCase aliases. Invalid rows
  are rejected individually; returns `{:ok, accepted}` where `accepted` is the
  number of newly inserted rows (replayed rows are not counted), or
  `{:error, :batch_too_large}`.
  """
  def record_events(device_token_id, events) when is_list(events) do
    if length(events) > @max_batch_size do
      {:error, :batch_too_large}
    else
      rows = Enum.flat_map(events, &to_insert_row(&1, device_token_id))

      {count, _} =
        Repo.insert_all(KioskEvent, rows,
          on_conflict: :nothing,
          conflict_target: [:session_id, :type, :occurred_at]
        )

      {:ok, count}
    end
  end

  def record_events(_, _), do: {:error, :invalid_batch}

  def max_batch_size, do: @max_batch_size

  @doc "Groups a session's events for analytics."
  def events_for_session(session_id) do
    Repo.all(
      from e in KioskEvent, where: e.session_id == ^session_id, order_by: [asc: e.occurred_at]
    )
  end

  @doc "Counts events by type for fleet analytics dashboards."
  def count_by_type do
    from(e in KioskEvent,
      group_by: e.type,
      select: {e.type, count(e.id)}
    )
    |> Repo.all()
  end

  # ── Row normalization ─────────────────────────────────────────────────────

  defp to_insert_row(event, device_token_id) when is_map(event) do
    session = event["session_id"] || event["sessionId"]

    event_type = event["type"] || event["event_type"]
    payload = event["payload"] || %{}

    occurred_at =
      case event["occurred_at"] || event["timestamp"] do
        %DateTime{} = dt -> dt
        timestamp when is_binary(timestamp) -> parse_timestamp(timestamp)
        _ -> nil
      end

    with true <- is_binary(session) and session != "",
         true <- is_binary(event_type) and event_type != "",
         %DateTime{} <- occurred_at do
      [
        %{
          session_id: session,
          type: String.slice(event_type, 0, 100),
          occurred_at: DateTime.truncate(occurred_at, :microsecond),
          payload: payload,
          device_token_id: device_token_id,
          inserted_at: DateTime.utc_now() |> DateTime.truncate(:second),
          updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
        }
      ]
    else
      _ -> []
    end
  end

  defp to_insert_row(_event, _), do: []

  defp parse_timestamp(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, dt, _offset} ->
        dt

      _ ->
        case NaiveDateTime.from_iso8601(timestamp) do
          {:ok, ndt} -> DateTime.from_naive!(ndt, "Etc/UTC")
          _ -> nil
        end
    end
  end
end
