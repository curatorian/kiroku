defmodule KirokuWeb.SwordV2Test do
  use KirokuWeb.ConnCase, async: true

  alias Kiroku.{Accounts, ApiTokens, Repository, Repo}
  alias Kiroku.Accounts.User

  # Tests the SWORD v2 deposit API: Service Document, Atom entry deposit,
  # Statement retrieval. Uses the same API token auth as the REST API.

  defp create_user(type) do
    {:ok, user} =
      Accounts.register_user(%{
        "email" => "sword-#{System.unique_integer([:positive])}@example.test",
        "password" => "password123456"
      })

    if type != :submitter do
      user |> User.role_changeset(%{user_type: type}) |> Repo.update!()
    else
      user
    end
  end

  defp authed_conn(%{id: _} = user) do
    {:ok, raw, _} = ApiTokens.create_token(user, "sword-test")
    build_conn() |> put_req_header("authorization", "Bearer #{raw}")
  end

  defp create_collection do
    handle = "sword-comm-#{System.unique_integer([:positive])}"

    {:ok, community} =
      Repository.create_community(%{"name" => "SWORD Community", "handle" => handle})

    {:ok, collection} =
      Repository.create_collection(%{
        "name" => "SWORD Collection",
        "community_id" => community.id,
        "handle" => "sword-coll-#{System.unique_integer([:positive])}"
      })

    collection
  end

  # ── Service Document ────────────────────────────────────────────────────────

  describe "GET /sword-v2/service-document" do
    test "returns the Service Document listing collections as Col-IRIs" do
      user = create_user(:admin)
      coll = create_collection()

      response =
        authed_conn(user)
        |> put_req_header("accept", "application/atomserv+xml")
        |> get(~p"/sword-v2/service-document")

      assert response(response, 200)

      body = response(response, 200)
      # Service document has the SWORD version and workspace structure.
      assert body =~ "sword:version"
      assert body =~ "SWORD Community"
      assert body =~ coll.handle
      # The Col-IRI href matches the collection deposit endpoint.
      assert body =~ "/sword-v2/collection/#{coll.handle}"
    end

    test "returns 401 without authentication" do
      response = build_conn() |> get(~p"/sword-v2/service-document")
      assert response(response, 401)
    end
  end

  # ── Atom entry deposit ──────────────────────────────────────────────────────

  describe "POST /sword-v2/collection/:collection_handle" do
    test "creates a draft item from a valid Atom entry" do
      user = create_user(:submitter)
      coll = create_collection()

      atom_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <entry xmlns="http://www.w3.org/2005/Atom"
             xmlns:dcterms="http://purl.org/dc/terms/">
        <title>SWORD-Deposited Thesis</title>
        <dcterms:abstract>Abstract deposited via SWORD v2.</dcterms:abstract>
        <dcterms:creator>Depositing Author</dcterms:creator>
        <dcterms:type>skripsi</dcterms:type>
      </entry>
      """

      response =
        authed_conn(user)
        |> put_req_header("content-type", "application/atom+xml;type=entry")
        |> post(~p"/sword-v2/collection/#{coll.handle}", atom_xml)

      assert response(response, 201)

      body = response(response, 201)
      assert body =~ "SWORD-Deposited Thesis"
      assert body =~ "sword:state"

      # Verify the item was actually created as a draft (search_items only
      # finds published items, so query directly).
      import Ecto.Query

      item =
        Kiroku.Repo.one(
          from i in Kiroku.Repository.Item, where: i.title == "SWORD-Deposited Thesis"
        )

      assert item != nil
      assert item.status == :draft
    end

    test "returns 404 for an unknown collection handle" do
      user = create_user(:submitter)

      response =
        authed_conn(user)
        |> put_req_header("content-type", "application/atom+xml")
        |> post(~p"/sword-v2/collection/nonexistent", "<entry/>")

      assert response(response, 404)
      assert response(response, 404) =~ "Collection not found"
    end

    test "returns 400 for a malformed Atom entry" do
      user = create_user(:submitter)
      coll = create_collection()

      response =
        authed_conn(user)
        |> put_req_header("content-type", "application/atom+xml")
        |> post(~p"/sword-v2/collection/#{coll.handle}", "<not valid xml")

      assert response(response, 400)
    end

    test "returns 401 without authentication" do
      coll = create_collection()

      response =
        build_conn()
        |> put_req_header("content-type", "application/atom+xml")
        |> post(~p"/sword-v2/collection/#{coll.handle}", "<entry/>")

      assert response(response, 401)
    end
  end

  # ── Statement ───────────────────────────────────────────────────────────────

  describe "GET /sword-v2/statement/:item_handle" do
    test "returns the SWORD Statement for a deposited item" do
      user = create_user(:admin)
      coll = create_collection()

      {:ok, item} =
        Repository.create_item(%{
          "title" => "Statement Test Item",
          "collection_id" => coll.id,
          "handle" => "stmt-#{System.unique_integer([:positive])}",
          "status" => "published",
          "discoverable" => true
        })

      response =
        authed_conn(user)
        |> get(~p"/sword-v2/statement/#{item.handle}")

      assert response(response, 200)
      body = response(response, 200)
      assert body =~ "Statement for Statement Test Item"
      assert body =~ "Published"
    end

    test "returns 404 for an unknown item handle" do
      user = create_user(:admin)

      response =
        authed_conn(user)
        |> get(~p"/sword-v2/statement/nonexistent")

      assert response(response, 404)
      assert response(response, 404) =~ "Item not found"
    end
  end
end
