defmodule KirokuWeb.Api.V1.ItemLifecycleAuthTest do
  use KirokuWeb.ConnCase, async: true

  alias Kiroku.{ApiTokens, Repository, Repo}

  # ── Fixtures ───────────────────────────────────────────────────────────────

  defp create_user(type) do
    {:ok, user} =
      Kiroku.Accounts.register_user(%{
        "email" => "lifecycle-#{System.unique_integer([:positive])}@example.test",
        "password" => "password123456"
      })

    if type != :submitter do
      user |> Kiroku.Accounts.User.role_changeset(%{user_type: type}) |> Repo.update!()
    else
      user
    end
  end

  defp authed_conn(user) do
    {:ok, raw, _} = ApiTokens.create_token(user, "test-token")
    build_conn() |> put_req_header("authorization", "Bearer #{raw}")
  end

  defp collection do
    {:ok, community} =
      Repository.create_community(%{
        "name" => "C",
        "handle" => "lifecycle-#{System.unique_integer([:positive])}"
      })

    {:ok, collection} =
      Repository.create_collection(%{
        "name" => "Coll",
        "community_id" => community.id,
        "handle" => "lifecycle-coll-#{System.unique_integer([:positive])}"
      })

    collection
  end

  defp submitted_item(user) do
    {:ok, item} =
      Repository.create_item(%{
        "title" => "Lifecycle Test",
        "collection_id" => collection().id,
        "submitter_id" => user.id,
        "status" => "submitted",
        "discoverable" => false
      })

    item
  end

  # ── PATCH must not allow self-publishing past review ───────────────────────

  test "submitter cannot self-publish their own submitted item via PATCH", %{conn: _conn} do
    user = create_user(:submitter)
    item = submitted_item(user)

    conn =
      authed_conn(user)
      |> patch(~p"/api/v1/items/#{item.id}", %{
        "item" => %{"status" => "published", "discoverable" => true, "abstract" => "Updated."}
      })

    assert %{"data" => _} = json_response(conn, 200)

    item = Repo.reload!(item)
    assert item.status == :submitted
    refute item.discoverable
    assert item.abstract == "Updated."
  end

  test "admin can still publish through PATCH (lifecycle fields allowed)", %{conn: _conn} do
    submitter = create_user(:submitter)
    item = submitted_item(submitter)
    admin = create_user(:admin)

    conn =
      authed_conn(admin)
      |> patch(~p"/api/v1/items/#{item.id}", %{"item" => %{"status" => "published"}})

    assert %{"data" => _} = json_response(conn, 200)
    assert Repo.reload!(item).status == :published
  end

  # ── Query-parameter tokens are no longer accepted ──────────────────────────

  test "?token= authentication is rejected (header only)", %{conn: conn} do
    user = create_user(:submitter)
    {:ok, raw, _} = ApiTokens.create_token(user, "query-token")

    conn = get(conn, "/api/v1/items?token=#{raw}")
    assert json_response(conn, 401)
  end

  # ── Device tokens are scoped to kiosk endpoints ────────────────────────────

  test "device token cannot authenticate item routes", %{conn: _conn} do
    user = create_user(:submitter)
    {:ok, raw, api_token} = ApiTokens.create_token(user, "kiosk device", token_type: :device)
    {:ok, _} = ApiTokens.approve_token(api_token.id)

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{raw}")
      |> get(~p"/api/v1/items")

    assert json_response(conn, 401)
  end

  test "device token still works on kiosk routes", %{conn: _conn} do
    user = create_user(:submitter)
    {:ok, raw, _} = ApiTokens.create_token(user, "kiosk device", token_type: :device)

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{raw}")
      |> get(~p"/api/v1/kiosks/status")

    assert json_response(conn, 200)
  end

  # ── Invalid-token brute force is throttled ─────────────────────────────────

  test "repeated invalid tokens get throttled with 429", %{conn: _conn} do
    # A unique-to-this-suite IP so the shared 127.0.0.1 fail-counter (used by
    # other async tests with revoked tokens) never interferes.
    bad =
      build_conn()
      |> Map.put(:remote_ip, {192, 0, 2, 123})
      |> put_req_header("authorization", "Bearer kiroku_not_a_real_token")

    for _ <- 1..30 do
      assert json_response(get(bad, ~p"/api/v1/items"), 401)
    end

    assert response(get(bad, ~p"/api/v1/items"), 429)
  end
end
