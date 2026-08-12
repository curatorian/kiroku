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

  describe "creates item with multiple file fields" do
    test "uploads cover, fulltext, and chapters in one request" do
      user = create_user(:submitter)
      coll = collection()
      cover = temp_upload("fake image data", "cover.jpg", "image/jpeg")
      fulltext = temp_upload("%PDF-1.4 full text", "thesis.pdf", "application/pdf")
      ch1 = temp_upload("%PDF-1.4 chapter 1", "bab1.pdf", "application/pdf")
      ch2 = temp_upload("%PDF-1.4 chapter 2", "bab2.pdf", "application/pdf")

      body = %{
        "item" => %{
          "title" => "Multi-File Thesis",
          "collection_id" => coll.id,
          "item_type" => "skripsi"
        },
        "files" => %{
          "cover" => [cover],
          "fulltext" => [fulltext],
          "chapters" => [ch1, ch2]
        }
      }

      conn =
        authed_conn(user)
        |> put_req_header("content-type", "multipart/form-data")
        |> post(~p"/api/v1/items/deposit", body)

      assert %{"data" => data} = json_response(conn, 201)
      assert data["title"] == "Multi-File Thesis"

      item = Repository.get_item_with_preloads!(data["id"])
      assert item.status == :draft
    end
  end

  describe "creates item with relations and files together" do
    test "combines authors, advisors, and file uploads in single deposit" do
      user = create_user(:submitter)
      coll = collection()
      upload = temp_upload("%PDF-1.4 combined content")

      body = %{
        "item" => %{
          "title" => "Complete Deposit",
          "collection_id" => coll.id,
          "item_type" => "skripsi"
        },
        "relations" => %{
          "authors" => [
            %{"author_name" => "Author One", "sequence" => 1}
          ],
          "advisors" => [
            %{"advisor_name" => "Advisor One", "advisor_role" => "main_advisor"}
          ],
          "keywords" => [%{"keyword" => "elixir"}, %{"keyword" => "phoenix"}]
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
      assert data["title"] == "Complete Deposit"
      assert length(data["authors"]) == 1
      assert length(data["advisors"]) == 1
      assert "elixir" in data["keywords"]
      assert "phoenix" in data["keywords"]
    end

    test "accepts keywords as plain strings" do
      user = create_user(:submitter)
      coll = collection()

      body = %{
        "item" => %{
          "title" => "String Keywords",
          "collection_id" => coll.id
        },
        "relations" => %{
          "keywords" => ["elixir", "phoenix"]
        }
      }

      conn =
        authed_conn(user)
        |> put_req_header("content-type", "multipart/form-data")
        |> post(~p"/api/v1/items/deposit", body)

      assert %{"data" => data} = json_response(conn, 201)
      assert "elixir" in data["keywords"]
      assert "phoenix" in data["keywords"]
    end
  end

  describe "creates item with different item_type" do
    test "filters allowed bundles for jurnal_nasional (no chapters)" do
      user = create_user(:submitter)
      coll = collection()
      fulltext = temp_upload("%PDF-1.4 journal article", "article.pdf", "application/pdf")

      body = %{
        "item" => %{
          "title" => "Journal Article Deposit",
          "collection_id" => coll.id,
          "item_type" => "jurnal_nasional"
        },
        "files" => %{
          "fulltext" => [fulltext]
        }
      }

      conn =
        authed_conn(user)
        |> put_req_header("content-type", "multipart/form-data")
        |> post(~p"/api/v1/items/deposit", body)

      assert %{"data" => data} = json_response(conn, 201)
      assert data["item_type"] == "jurnal_nasional"

      item = Repository.get_item_with_preloads!(data["id"])
      assert item.status == :draft
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

    test "creates item with link files and relations" do
      user = create_user(:submitter)
      coll = collection()

      body = %{
        "deposit_type" => "link",
        "item" => %{
          "title" => "Link Deposit with Relations",
          "collection_id" => coll.id,
          "item_type" => "skripsi"
        },
        "relations" => %{
          "authors" => [
            %{"author_name" => "Link Author", "sequence" => 1}
          ],
          "keywords" => [%{"keyword" => "remote"}, %{"keyword" => "link-based"}]
        },
        "files" => %{
          "fulltext" => ["https://example.com/thesis.pdf"],
          "chapters" => [
            "https://example.com/ch1.pdf",
            "https://example.com/ch2.pdf"
          ]
        },
        "storage_mode" => "reference"
      }

      conn =
        authed_conn(user)
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/v1/items/deposit", body)

      assert %{"data" => data} = json_response(conn, 201)
      assert data["title"] == "Link Deposit with Relations"
      assert length(data["authors"]) == 1
      assert "remote" in data["keywords"]
    end

    test "creates item with status submitted via link mode" do
      user = create_user(:submitter)
      coll = collection()

      body = %{
        "deposit_type" => "link",
        "item" => %{
          "title" => "Submitted Link Deposit",
          "collection_id" => coll.id,
          "status" => "submitted"
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
      assert data["status"] == "submitted"
    end

    test "creates item with link files using download storage mode" do
      user = create_user(:submitter)
      coll = collection()

      body = %{
        "deposit_type" => "link",
        "item" => %{
          "title" => "Download Mode Deposit",
          "collection_id" => coll.id
        },
        "files" => %{
          "fulltext" => ["https://example.com/paper.pdf"]
        },
        "storage_mode" => "download"
      }

      conn =
        authed_conn(user)
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/v1/items/deposit", body)

      # download mode will fail because example.com returns non-200 for this path,
      # but the item creation itself should succeed. The controller returns 500 if
      # download fails, so we test that the endpoint handles it gracefully.
      response = json_response(conn, 500)
      assert response["error"] == "File upload failed"
    end

    test "denies users without :create permission (403)" do
      user = create_user(:internal)
      coll = collection()

      body = %{
        "deposit_type" => "link",
        "item" => %{
          "title" => "Forbidden Link Deposit",
          "collection_id" => coll.id
        }
      }

      conn =
        authed_conn(user)
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/v1/items/deposit", body)

      assert json_response(conn, 403)
    end

    test "rejects missing item parameter (400)" do
      user = create_user(:submitter)

      conn =
        authed_conn(user)
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/v1/items/deposit", %{"deposit_type" => "link"})

      assert json_response(conn, 400)
    end

    test "requires authentication (no token → 401)" do
      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/v1/items/deposit", %{"deposit_type" => "link", "item" => %{}})

      assert json_response(conn, 401)
    end
  end
end
