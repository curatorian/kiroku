defmodule KirokuWeb.Api.V1.KioskEventsApiTest do
  use KirokuWeb.ConnCase, async: true

  import Ecto.Query

  alias Kiroku.{Accounts, ApiTokens, KioskEvent, Repo}

  defp create_user do
    {:ok, user} =
      Accounts.register_user(%{
        "email" => "events-#{System.unique_integer([:positive])}@example.test",
        "password" => "password123456"
      })

    user
  end

  defp session_rows(session_id) do
    from(e in KioskEvent, where: e.session_id == ^session_id) |> Repo.aggregate(:count)
  end

  setup do
    user = create_user()
    {:ok, raw, _} = ApiTokens.create_token(user, "events token", token_type: :device)

    %{raw_token: raw}
  end

  defp authed_conn(raw) do
    build_conn() |> put_req_header("authorization", "Bearer #{raw}")
  end

  @ts "2026-10-27T09:01:23.500000Z"

  test "accepts a batch and reports the accepted count", %{raw_token: raw} do
    events = [
      %{
        "sessionId" => "s1",
        "type" => "page_view",
        "timestamp" => @ts,
        "payload" => %{"item" => "a"}
      },
      %{"sessionId" => "s1", "type" => "open", "timestamp" => @ts}
    ]

    conn = authed_conn(raw) |> post(~p"/api/v1/events", %{"events" => events})

    assert json_response(conn, 202) == %{"accepted" => 2, "total" => 2}
    assert session_rows("s1") == 2
  end

  test "replaying the same batch is idempotent", %{raw_token: raw} do
    events = [%{"sessionId" => "s2", "type" => "page_view", "timestamp" => @ts, "payload" => %{}}]

    _first = authed_conn(raw) |> post(~p"/api/v1/events", %{"events" => events})
    replay = authed_conn(raw) |> post(~p"/api/v1/events", %{"events" => events})

    assert json_response(replay, 202) == %{"accepted" => 0, "total" => 1}
    assert session_rows("s2") == 1
  end

  test "skips rows with missing required fields", %{raw_token: raw} do
    events = [
      %{"sessionId" => "s3", "type" => "page_view", "timestamp" => @ts},
      # missing timestamp
      %{"sessionId" => "s3", "type" => "page_view"},
      # missing sessionId
      %{"type" => "page_view", "timestamp" => @ts},
      %{"sessionId" => "s3", "type" => 123, "timestamp" => @ts}
    ]

    conn = authed_conn(raw) |> post(~p"/api/v1/events", %{"events" => events})

    assert json_response(conn, 202) == %{"accepted" => 1, "total" => 4}
    assert session_rows("s3") == 1
  end

  test "rejects oversized batches", %{raw_token: raw} do
    events = List.duplicate(%{"sessionId" => "s4", "type" => "t", "timestamp" => @ts}, 501)

    conn = authed_conn(raw) |> post(~p"/api/v1/events", %{"events" => events})

    assert json_response(conn, 400) == %{
             "error" => "bad_request",
             "message" => "Events batch exceeds 500 entries"
           }
  end

  test "rejects a request without an events array", %{raw_token: raw} do
    conn = authed_conn(raw) |> post(~p"/api/v1/events", %{"something" => "else"})

    assert json_response(conn, 400) == %{
             "error" => "bad_request",
             "message" => "Missing 'events' array"
           }
  end

  test "KioskEvents.record_events context stores payload + attribution", %{raw_token: _raw} do
    {:ok, user} = create_user_for_api_token()
    {:ok, raw, api_token} = ApiTokens.create_token(user, "attrib token", token_type: :device)

    events = [
      %{
        "sessionId" => "s5",
        "type" => "session_start",
        "timestamp" => @ts,
        "payload" => %{"build" => "42"}
      }
    ]

    conn = build_conn() |> put_req_header("authorization", "Bearer #{raw}")
    conn = post(conn, ~p"/api/v1/events", %{"events" => events})
    assert json_response(conn, 202)["accepted"] == 1

    row = from(e in KioskEvent, where: e.session_id == "s5") |> Repo.one!()
    assert row.type == "session_start"
    assert row.payload == %{"build" => "42"}
    assert row.device_token_id == api_token.id
    assert row.occurred_at == ~U[2026-10-27 09:01:23.500000Z]
  end

  defp create_user_for_api_token do
    Accounts.register_user(%{
      "email" => "events-owner-#{System.unique_integer([:positive])}@example.test",
      "password" => "password123456"
    })
  end
end
