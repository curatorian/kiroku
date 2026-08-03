defmodule KirokuWeb.Api.V1.DepositApiTest do
  use KirokuWeb.ConnCase, async: true

  alias Kiroku.{Accounts, ApiTokens, Repository, Repo}
  alias Kiroku.Accounts.User

  # ── Fixtures ───────────────────────────────────────────────────────────────

  defp create_user(type) do
    {:ok, user} =
      Accounts.register_user(%{
        "email" => "deposit-#{System.unique_integer([:positive])}@example.test",
        "password" => "password123456"
      })

    if type != :submitter do
      user |> User.role_changeset(%{user_type: type}) |> Repo.update!()
    else
      user
    end
  end

  defp authed_conn(%{id: _} = user) do
    {:ok, raw, _} = ApiTokens.create_token(user, "deposit-test")
    build_conn() |> put_req_header("authorization", "Bearer #{raw}")
  end

  defp collection do
    handle = "dep-comm-#{System.unique_integer([:positive])}"

    {:ok, community} =
      Repository.create_community(%{"name" => "Deposit Community", "handle" => handle})

    {:ok, collection} =
      Repository.create_collection(%{
        "name" => "Deposit Collection",
        "community_id" => community.id,
        "handle" => "dep-coll-#{System.unique_integer([:positive])}"
      })

    collection
  end

  defp temp_upload(content, filename \\ "thesis.pdf", content_type \\ "application/pdf") do
    path = Path.join(System.tmp_dir!(), "deposit-upload-#{System.unique_integer([:positive])}")
    File.write!(path, content)
    %Plug.Upload{path: path, filename: filename, content_type: content_type}
  end

  # ── POST /api/v1/items/deposit ─────────────────────────────────────────────

  describe "multipart deposit" do
    test "creates a draft item with metadata only" do
      user = create_user(:submitter)
      coll = collection()

      body = %{
        "item" => %{
          "title" => "Deposited Thesis",
          "collection_id" => coll.id,
          "abstract" => "Full deposit via REST API.",
          "item_type" => "skripsi"
        }
      }

      conn =
        authed_conn(user)
        |> put_req_header("content-type", "multipart/form-data")
        |> post(~p"/api/v1/items/deposit", body)

      assert %{"data" => data} = json_response(conn, 201)
      assert data["title"] == "Deposited Thesis"
      assert data["abstract"] == "Full deposit via REST API."
      assert data["item_type"] == "skripsi"
      assert data["status"] == "draft"

      item = Repository.get_item_with_preloads!(data["id"])
      assert item.submitter_id == user.id
    end

    test "creates item with relations (authors and advisors)" do
      user = create_user(:submitter)
      coll = collection()

      body = %{
        "item" => %{
          "title" => "Thesis with Relations",
          "collection_id" => coll.id
        },
        "relations" => %{
          "authors" => [
            %{"author_name" => "Author One", "sequence" => 1},
            %{"author_name" => "Author Two", "sequence" => 2}
          ],
          "advisors" => [
            %{"advisor_name" => "Advisor One", "advisor_role" => "main_advisor"}
          ]
        }
      }

      conn =
        authed_conn(user)
        |> put_req_header("content-type", "multipart/form-data")
        |> post(~p"/api/v1/items/deposit", body)

      assert %{"data" => data} = json_response(conn, 201)
      assert data["title"] == "Thesis with Relations"
      assert length(data["authors"]) == 2
      assert length(data["advisors"]) == 1
    end

    test "creates item with file uploads" do
      user = create_user(:submitter)
      coll = collection()
      upload = temp_upload("%PDF-1.4 deposited content")

      body = %{
        "item" => %{
          "title" => "Thesis with Files",
          "collection_id" => coll.id,
          "item_type" => "skripsi"
        },
        "files" => %{
          "fulltext" => [upload]
        }
      }

      conn =
        authed_conn(user)
        |> put_req_header("content-type", "multipart/form-data")
        |> post(~p"/api/v1/items/deposit", body)

      assert %{"data" => data} = json_response(conn, 201)
      assert data["title"] == "Thesis with Files"

      item = Repository.get_item_with_preloads!(data["id"])
      assert item.status == :draft
    end

    test "creates item with status submitted" do
      user = create_user(:submitter)
      coll = collection()

      body = %{
        "item" => %{
          "title" => "Submitted Thesis",
          "collection_id" => coll.id,
          "status" => "submitted"
        }
      }

      conn =
        authed_conn(user)
        |> put_req_header("content-type", "multipart/form-data")
        |> post(~p"/api/v1/items/deposit", body)

      assert %{"data" => data} = json_response(conn, 201)
      assert data["status"] == "submitted"
    end

    test "denies users without :create permission (403)" do
      user = create_user(:internal)
      coll = collection()

      body = %{
        "item" => %{
          "title" => "Forbidden Deposit",
          "collection_id" => coll.id
        }
      }

      conn =
        authed_conn(user)
        |> put_req_header("content-type", "multipart/form-data")
        |> post(~p"/api/v1/items/deposit", body)

      assert json_response(conn, 403)
    end

    test "rejects missing item parameter (400)" do
      user = create_user(:submitter)

      conn =
        authed_conn(user)
        |> put_req_header("content-type", "multipart/form-data")
        |> post(~p"/api/v1/items/deposit", %{})

      assert json_response(conn, 400)
    end

    test "rejects invalid payload with 422" do
      user = create_user(:submitter)
      coll = collection()

      body = %{
        "item" => %{
          "collection_id" => coll.id
        }
      }

      conn =
        authed_conn(user)
        |> put_req_header("content-type", "multipart/form-data")
        |> post(~p"/api/v1/items/deposit", body)

      assert %{"errors" => errors} = json_response(conn, 422)
      assert errors["title"]
    end

    test "requires authentication (no token → 401)" do
      conn =
        build_conn()
        |> put_req_header("content-type", "multipart/form-data")
        |> post(~p"/api/v1/items/deposit", %{"item" => %{}})

      assert json_response(conn, 401)
    end
  end

  # ── JSON deposit (link-based files) ────────────────────────────────────────

  describe "json deposit with link files" do
    test "creates item with link-based file references" do
      user = create_user(:submitter)
      coll = collection()

      body = %{
        "deposit_type" => "link",
        "item" => %{
          "title" => "Link Deposit",
          "collection_id" => coll.id
        },
        "files" => %{
          "fulltext" => ["https://example.com/paper.pdf"]
        },
        "storage_mode" => "reference"
      }

      conn =
        authed_conn(user)
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/v1/items/deposit", body)

      assert %{"data" => data} = json_response(conn, 201)
      assert data["title"] == "Link Deposit"

      item = Repository.get_item_with_preloads!(data["id"])
      assert item.status == :draft
    end
  end
end
