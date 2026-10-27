defmodule KirokuWeb.Api.V1.CollectionApiTest do
  use KirokuWeb.ConnCase, async: true

  alias Kiroku.{Accounts, ApiTokens, Repository, Repo}
  alias Kiroku.Accounts.User

  # ── Fixtures ───────────────────────────────────────────────────────────────

  defp create_user(type) do
    {:ok, user} =
      Accounts.register_user(%{
        "email" => "api-#{System.unique_integer([:positive])}@example.test",
        "password" => "password123456"
      })

    if type != :submitter do
      user |> User.role_changeset(%{user_type: type}) |> Repo.update!()
    else
      user
    end
  end

  defp authed_conn(%{id: _} = user) do
    {:ok, raw, _} = ApiTokens.create_token(user, "test-token")
    build_conn() |> put_req_header("authorization", "Bearer #{raw}")
  end

  defp community do
    handle = "comm-#{System.unique_integer([:positive])}"

    {:ok, community} =
      Repository.create_community(%{"name" => "Community", "handle" => handle})

    community
  end

  defp collection do
    comm = community()

    handle = "coll-#{System.unique_integer([:positive])}"

    {:ok, collection} =
      Repository.create_collection(%{
        "name" => "Collection",
        "community_id" => comm.id,
        "handle" => handle
      })

    collection
  end

  # ── GET /api/v1/collections ─────────────────────────────────────────────

  describe "list collections" do
    test "returns all active collections", %{conn: _conn} do
      user = create_user(:submitter)
      coll = collection()

      conn =
        authed_conn(user)
        |> get(~p"/api/v1/collections")

      assert %{"data" => data} = json_response(conn, 200)
      assert is_list(data)
      assert Enum.any?(data, &(&1["id"] == coll.id))
    end

    test "filters by community_id", %{conn: _conn} do
      user = create_user(:submitter)
      comm = community()
      coll = collection()

      conn =
        authed_conn(user)
        |> get(~p"/api/v1/collections?community_id=#{comm.id}")

      assert %{"data" => data} = json_response(conn, 200)
      assert Enum.all?(data, &(&1["community_id"] == comm.id))
      refute Enum.any?(data, &(&1["id"] == coll.id))
    end

    test "returns 401 without auth token", %{conn: _conn} do
      conn = build_conn() |> get(~p"/api/v1/collections")
      assert json_response(conn, 401)
    end
  end

  # ── GET /api/v1/collections/:id ────────────────────────────────────────

  describe "get collection" do
    test "returns a single collection with item count", %{conn: _conn} do
      user = create_user(:submitter)
      coll = collection()

      conn =
        authed_conn(user)
        |> get(~p"/api/v1/collections/#{coll.id}")

      assert %{"data" => data} = json_response(conn, 200)
      assert data["id"] == coll.id
      assert data["name"] == coll.name
      assert data["item_count"] == 0
      assert data["community"]["id"] == coll.community_id
    end

    test "returns 404 for unknown collection", %{conn: _conn} do
      user = create_user(:submitter)
      fake_id = Ecto.UUID.generate()

      conn =
        authed_conn(user)
        |> get(~p"/api/v1/collections/#{fake_id}")

      assert json_response(conn, 404)
    end
  end

  # ── POST /api/v1/collections ───────────────────────────────────────────

  describe "create collection" do
    test "creates a collection as admin", %{conn: _conn} do
      user = create_user(:admin)
      comm = community()

      body = %{
        "collection" => %{
          "name" => "Teknik Informatika",
          "handle" => "ti-#{System.unique_integer([:positive])}",
          "short_description" => "Computer Science",
          "description" => "Computer Science department works",
          "community_id" => comm.id,
          "position" => 1,
          "access_level" => "open",
          "default_item_access_level" => "internal"
        }
      }

      conn =
        authed_conn(user)
        |> post(~p"/api/v1/collections", body)

      assert %{"data" => data} = json_response(conn, 201)
      assert data["name"] == "Teknik Informatika"
      assert data["handle"] =~ "ti-"
      assert data["community_id"] == comm.id

      # Verify persisted
      coll = Repository.get_collection!(data["id"])
      assert coll.name == "Teknik Informatika"
      assert coll.community_id == comm.id
    end

    test "returns 403 for non-admin users", %{conn: _conn} do
      user = create_user(:submitter)
      comm = community()

      body = %{
        "collection" => %{
          "name" => "Forbidden Collection",
          "handle" => "fc-#{System.unique_integer([:positive])}",
          "community_id" => comm.id
        }
      }

      conn =
        authed_conn(user)
        |> post(~p"/api/v1/collections", body)

      assert json_response(conn, 403)
    end

    test "returns 401 without auth token", %{conn: _conn} do
      comm = community()

      body = %{
        "collection" => %{
          "name" => "No Auth Collection",
          "handle" => "nac-#{System.unique_integer([:positive])}",
          "community_id" => comm.id
        }
      }

      conn = build_conn() |> post(~p"/api/v1/collections", body)
      assert json_response(conn, 401)
    end

    test "returns 422 for missing required fields", %{conn: _conn} do
      user = create_user(:admin)

      conn =
        authed_conn(user)
        |> post(~p"/api/v1/collections", %{"collection" => %{}})

      assert %{"fields" => _errors} = json_response(conn, 422)
      assert _errors["name"]
      assert _errors["community_id"]
    end

    test "returns 422 for duplicate handle", %{conn: _conn} do
      user = create_user(:admin)
      coll = collection()

      conn =
        authed_conn(user)
        |> post(~p"/api/v1/collections", %{
          "collection" => %{
            "name" => "Duplicate Handle",
            "handle" => coll.handle,
            "community_id" => coll.community_id
          }
        })

      assert %{"fields" => _errors} = json_response(conn, 422)
    end
  end
end
