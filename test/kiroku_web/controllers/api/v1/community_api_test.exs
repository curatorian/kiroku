defmodule KirokuWeb.Api.V1.CommunityApiTest do
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

  # ── GET /api/v1/communities ──────────────────────────────────────────────

  describe "list communities" do
    test "returns all active communities", %{conn: _conn} do
      user = create_user(:submitter)
      comm = community()

      conn =
        authed_conn(user)
        |> get(~p"/api/v1/communities")

      assert %{"data" => data} = json_response(conn, 200)
      assert is_list(data)
      assert Enum.any?(data, &(&1["id"] == comm.id))
    end

    test "returns 401 without auth token", %{conn: _conn} do
      conn = build_conn() |> get(~p"/api/v1/communities")
      assert json_response(conn, 401)
    end
  end

  # ── GET /api/v1/communities/:id ─────────────────────────────────────────

  describe "get community" do
    test "returns a single community with collections", %{conn: _conn} do
      user = create_user(:submitter)
      comm = community()

      conn =
        authed_conn(user)
        |> get(~p"/api/v1/communities/#{comm.id}")

      assert %{"data" => data} = json_response(conn, 200)
      assert data["id"] == comm.id
      assert data["name"] == comm.name
      assert data["collections"] == []
    end

    test "returns 404 for unknown community", %{conn: _conn} do
      user = create_user(:submitter)
      fake_id = Ecto.UUID.generate()

      conn =
        authed_conn(user)
        |> get(~p"/api/v1/communities/#{fake_id}")

      assert json_response(conn, 404)
    end
  end

  # ── POST /api/v1/communities ────────────────────────────────────────────

  describe "create community" do
    test "creates a community as superadmin", %{conn: _conn} do
      user = create_user(:superadmin)

      body = %{
        "community" => %{
          "name" => "Fakultas Teknik",
          "handle" => "ft-#{System.unique_integer([:positive])}",
          "short_description" => "Faculty of Engineering",
          "description" => "Academic works from the Faculty of Engineering",
          "position" => 1,
          "access_level" => "open"
        }
      }

      conn =
        authed_conn(user)
        |> post(~p"/api/v1/communities", body)

      assert %{"data" => data} = json_response(conn, 201)
      assert data["name"] == "Fakultas Teknik"
      assert data["handle"] =~ "ft-"
      assert data["short_description"] == "Faculty of Engineering"

      # Verify persisted
      community = Repository.get_community!(data["id"])
      assert community.name == "Fakultas Teknik"
    end

    test "returns 403 for non-superadmin users", %{conn: _conn} do
      user = create_user(:admin)

      body = %{
        "community" => %{
          "name" => "Forbidden Community",
          "handle" => "fc-#{System.unique_integer([:positive])}"
        }
      }

      conn =
        authed_conn(user)
        |> post(~p"/api/v1/communities", body)

      assert json_response(conn, 403)
    end

    test "returns 401 without auth token", %{conn: _conn} do
      body = %{
        "community" => %{
          "name" => "No Auth Community",
          "handle" => "nac-#{System.unique_integer([:positive])}"
        }
      }

      conn = build_conn() |> post(~p"/api/v1/communities", body)
      assert json_response(conn, 401)
    end

    test "returns 422 for missing required fields", %{conn: _conn} do
      user = create_user(:superadmin)

      conn =
        authed_conn(user)
        |> post(~p"/api/v1/communities", %{"community" => %{}})

      assert %{"errors" => _errors} = json_response(conn, 422)
      assert _errors["name"]
    end

    test "returns 422 for duplicate handle", %{conn: _conn} do
      user = create_user(:superadmin)
      comm = community()

      conn =
        authed_conn(user)
        |> post(~p"/api/v1/communities", %{
          "community" => %{
            "name" => "Duplicate Handle",
            "handle" => comm.handle
          }
        })

      assert %{"errors" => _errors} = json_response(conn, 422)
    end
  end
end
