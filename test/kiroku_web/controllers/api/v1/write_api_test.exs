defmodule KirokuWeb.Api.V1.WriteApiTest do
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

  defp collection do
    handle = "comm-#{System.unique_integer([:positive])}"

    {:ok, community} =
      Repository.create_community(%{"name" => "C", "handle" => handle})

    {:ok, collection} =
      Repository.create_collection(%{
        "name" => "Coll",
        "community_id" => community.id,
        "handle" => "coll-#{System.unique_integer([:positive])}"
      })

    collection
  end

  defp temp_upload(content, filename \\ "thesis.pdf", content_type \\ "application/pdf") do
    path = Path.join(System.tmp_dir!(), "api-upload-#{System.unique_integer([:positive])}")
    File.write!(path, content)
    %Plug.Upload{path: path, filename: filename, content_type: content_type}
  end

  # ── POST /api/v1/items ────────────────────────────────────────────────────

  describe "create item" do
    test "creates a draft item owned by the API user", %{conn: _conn} do
      user = create_user(:submitter)
      coll = collection()

      body = %{
        "item" => %{
          "title" => "API-Deposited Thesis",
          "collection_id" => coll.id,
          "abstract" => "Deposited via the REST API."
        }
      }

      conn = authed_conn(user) |> post(~p"/api/v1/items", body)

      assert %{"data" => data} = json_response(conn, 201)
      assert data["title"] == "API-Deposited Thesis"
      assert data["submitter_id"] == nil || data["collection"]["id"] == coll.id

      # The item is persisted and owned by the API user.
      item = Repository.get_item_with_preloads!(data["id"])
      assert item.submitter_id == user.id
      assert item.status == :draft
    end

    test "denies users without :create permission (403)", %{conn: _conn} do
      # :internal users cannot create items per the role rules.
      user = create_user(:internal)

      conn =
        authed_conn(user)
        |> post(~p"/api/v1/items", %{
          "item" => %{"title" => "x", "collection_id" => collection().id}
        })

      assert json_response(conn, 403)
    end

    test "rejects invalid payload with 422", %{conn: _conn} do
      user = create_user(:submitter)

      conn =
        authed_conn(user)
        |> post(~p"/api/v1/items", %{"item" => %{"collection_id" => collection().id}})

      assert %{"errors" => errors} = json_response(conn, 422)
      assert errors["title"]
    end

    test "requires authentication (no token → 401)", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/items", %{"item" => %{}})
      assert json_response(conn, 401)
    end
  end

  # ── PATCH /api/v1/items/:id ───────────────────────────────────────────────

  describe "update item" do
    test "updates a draft owned by the submitter", %{conn: _conn} do
      user = create_user(:submitter)
      coll = collection()

      {:ok, item} =
        Repository.create_item(%{
          "title" => "Old Title",
          "collection_id" => coll.id,
          "submitter_id" => user.id,
          "status" => "draft"
        })

      conn =
        authed_conn(user)
        |> patch(~p"/api/v1/items/#{item.id}", %{"item" => %{"abstract" => "New abstract."}})

      assert %{"data" => data} = json_response(conn, 200)
      assert data["abstract"] == "New abstract."
    end

    test "forbids updating another user's draft", %{conn: _conn} do
      owner = create_user(:submitter)
      other = create_user(:submitter)
      coll = collection()

      {:ok, item} =
        Repository.create_item(%{
          "title" => "Owner's Draft",
          "collection_id" => coll.id,
          "submitter_id" => owner.id,
          "status" => "draft"
        })

      conn =
        authed_conn(other)
        |> patch(~p"/api/v1/items/#{item.id}", %{"item" => %{"abstract" => "hijack"}})

      assert json_response(conn, 403)
    end

    test "404 for unknown item", %{conn: _conn} do
      user = create_user(:submitter)
      fake = Ecto.UUID.generate()

      conn =
        authed_conn(user)
        |> patch(~p"/api/v1/items/#{fake}", %{"item" => %{"abstract" => "x"}})

      assert json_response(conn, 404)
    end
  end

  # ── POST /api/v1/items/:id/bitstreams ─────────────────────────────────────

  describe "deposit bitstream" do
    test "uploads a file and creates a bitstream", %{conn: _conn} do
      user = create_user(:submitter)
      coll = collection()

      {:ok, item} =
        Repository.create_item(%{
          "title" => "Deposit Target",
          "collection_id" => coll.id,
          "submitter_id" => user.id,
          "status" => "draft"
        })

      upload = temp_upload("%PDF-1.4 uploaded via api")

      conn =
        authed_conn(user)
        |> put_req_header("accept", "application/json")
        |> post(~p"/api/v1/items/#{item.id}/bitstreams", %{
          "file" => upload,
          "bundle_name" => "ORIGINAL",
          "description" => "Full text"
        })

      assert %{"data" => data} = json_response(conn, 201)
      assert data["filename"] == "thesis.pdf"
      assert data["bundle_name"] == "ORIGINAL"

      # Bitstream persisted with a computed checksum.
      bs = Kiroku.Content.get_bitstream!(data["id"])
      assert bs.checksum
      assert bs.file_size > 0
    end

    test "forbids deposit by a non-editor", %{conn: _conn} do
      owner = create_user(:submitter)
      other = create_user(:submitter)
      coll = collection()

      {:ok, item} =
        Repository.create_item(%{
          "title" => "Guarded",
          "collection_id" => coll.id,
          "submitter_id" => owner.id,
          "status" => "draft"
        })

      conn =
        authed_conn(other)
        |> put_req_header("accept", "application/json")
        |> post(~p"/api/v1/items/#{item.id}/bitstreams", %{"file" => temp_upload("x")})

      assert json_response(conn, 403)
    end

    test "rejects an invalid bundle with 400", %{conn: _conn} do
      user = create_user(:submitter)
      coll = collection()

      {:ok, item} =
        Repository.create_item(%{
          "title" => "T",
          "collection_id" => coll.id,
          "submitter_id" => user.id,
          "status" => "draft"
        })

      conn =
        authed_conn(user)
        |> put_req_header("accept", "application/json")
        |> post(~p"/api/v1/items/#{item.id}/bitstreams", %{
          "file" => temp_upload("x"),
          "bundle_name" => "NOSUCHBUNDLE"
        })

      assert json_response(conn, 400)
    end
  end
end
