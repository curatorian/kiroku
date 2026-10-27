defmodule KirokuWeb.Api.V1.KioskEventController do
  @moduledoc """
  REST API v1 — visitor event ingestion (SPEC 7.6).

  POST /api/v1/events — accepts a batch of up to 500 visitor events:

      {"events": [
        {"sessionId": "...", "type": "page_view", "timestamp": "...", "payload": {}},
        ...
      ]}

  Idempotent per (session_id, type, timestamp); replaced rows in replays
  aren't counted twice. Content-Type: application/json only.
  """
  use KirokuWeb, :controller

  import KirokuWeb.Api.ErrorHelpers

  alias Kiroku.KioskEvents

  def create(conn, params) do
    events =
      case params do
        %{"events" => events} when is_list(events) -> events
        %{"batch" => events} when is_list(events) -> events
        events when is_list(events) -> events
        _ -> nil
      end

    cond do
      !events ->
        bad_request(conn, "Missing 'events' array")

      true ->
        device_token_id = conn.assigns[:api_token] && conn.assigns[:api_token].id

        case KioskEvents.record_events(device_token_id, events) do
          {:ok, accepted} ->
            put_status(conn, :accepted) |> json(%{accepted: accepted, total: length(events)})

          {:error, :batch_too_large} ->
            bad_request(conn, "Events batch exceeds #{KioskEvents.max_batch_size()} entries")

          {:error, :invalid_batch} ->
            bad_request(conn, "Invalid events payload")
        end
    end
  end
end
