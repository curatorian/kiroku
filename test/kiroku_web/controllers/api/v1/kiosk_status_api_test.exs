defmodule KirokuWeb.Api.V1.KioskStatusApiTest do
  use KirokuWeb.ConnCase, async: true

  alias Kiroku.{Accounts, ApiTokens, Kiosk}

  defp create_user do
    {:ok, user} =
      Accounts.register_user(%{
        "email" => "kiosk-#{System.unique_integer([:positive])}@example.test",
        "password" => "password123456"
      })

    user
  end

  defp token(user, type) do
    {:ok, raw, api_token} = ApiTokens.create_token(user, "kiosk #{type} token", token_type: type)
    %{raw: raw, api_token: api_token}
  end

  defp authed_conn(raw) do
    build_conn() |> put_req_header("authorization", "Bearer #{raw}")
  end

  describe "GET /api/v1/kiosks/status" do
    test "returns active + public tier for a user token" do
      user = create_user()
      %{raw: raw} = token(user, :user)

      conn = authed_conn(raw) |> get(~p"/api/v1/kiosks/status")
      body = json_response(conn, 200)

      assert body["state"] == "active"
      assert body["tier"] == "public"
      assert body["server_time"]
      assert body["policies"]["page_size_default"]
    end

    test "returns needs_reverify for an unapproved device token" do
      user = create_user()
      %{raw: raw} = token(user, :device)

      conn = authed_conn(raw) |> get(~p"/api/v1/kiosks/status")
      body = json_response(conn, 200)

      assert body["state"] == "needs_reverify"
      assert body["tier"] == "kiosk"
    end

    test "returns active for an approved device token" do
      user = create_user()
      %{raw: raw, api_token: api_token} = token(user, :device)
      {:ok, _} = ApiTokens.approve_token(api_token.id)

      conn = authed_conn(raw) |> get(~p"/api/v1/kiosks/status")
      assert json_response(conn, 200)["state"] == "active"
    end

    test "maintenance flag overrides the device state" do
      user = create_user()
      %{raw: raw, api_token: api_token} = token(user, :device)
      {:ok, _} = ApiTokens.approve_token(api_token.id)
      Kiosk.put_maintenance(true, "back at 10:00")

      conn = authed_conn(raw) |> get(~p"/api/v1/kiosks/status")
      assert json_response(conn, 200)["state"] == "maintenance"
    end

    test "policies/announcement/contact round-trip through the endpoint" do
      user = create_user()
      %{raw: raw} = token(user, :device)
      Kiosk.put_announcement("Library closes at 21:00")
      Kiosk.put_contact("kandaga@example.ac.id")
      Kiosk.put_policies(%{"allow_print" => false, "idle_seconds" => 120})

      conn = authed_conn(raw) |> get(~p"/api/v1/kiosks/status")
      body = json_response(conn, 200)

      assert body["announcement"] == "Library closes at 21:00"
      assert body["contact"] == "kandaga@example.ac.id"
      assert body["policies"]["allow_print"] == false
      assert body["policies"]["idle_seconds"] == 120
      # Untouched keys keep their defaults.
      assert body["policies"]["page_size_default"] == 20
    end

    test "revoked (deleted) device token reads as 401" do
      user = create_user()
      %{raw: raw, api_token: api_token} = token(user, :device)
      {:ok, _new_raw, _} = ApiTokens.rotate_token(api_token.id)

      # The original (now rotated = revoked) token is rejected.
      conn = authed_conn(raw) |> get(~p"/api/v1/kiosks/status")

      assert conn.status == 401
      assert json_response(conn, 401)["error"] == "unauthorized"
    end

    test "device token also authorizes regular API routes" do
      user = create_user()
      %{raw: raw} = token(user, :device)

      conn = authed_conn(raw) |> get(~p"/api/v1/communities")
      assert conn.status == 200
    end
  end
end
