defmodule KirokuWeb.Api.V1.ItemsListApiTest do
  use KirokuWeb.ConnCase, async: true

  alias Kiroku.{Accounts, ApiTokens, Repository, Repo}
  alias Kiroku.Accounts.User

  setup do
    user = create_user(:submitter)
    {:ok, raw, _} = ApiTokens.create_token(user, "list-token")
    %{raw_token: raw}
  end

  defp create_user(type) do
    {:ok, user} =
      Accounts.register_user(%{
        "email" => "list-#{System.unique_integer([:positive])}@example.test",
        "password" => "password123456"
      })

    if type != :submitter do
      user |> User.role_changeset(%{user_type: type}) |> Repo.update!()
    else
      user
    end
  end

  defp scope_fixture do
    {:ok, community} =
      Repository.create_community(%{
        "name" => "C",
        "handle" => "comm-#{System.unique_integer([:positive])}"
      })

    {:ok, collection} =
      Repository.create_collection(%{
        "name" => "Skripsi #{System.unique_integer([:positive])}",
        "community_id" => community.id,
        "handle" => "coll-#{System.unique_integer([:positive])}"
      })

    {community, collection}
  end

  defp create_published(collection, attrs) do
    {:ok, item} =
      Repository.create_item(
        Map.merge(
          %{
            "title" => "Title #{System.unique_integer([:positive])}",
            "collection_id" => collection.id,
            "status" => "published",
            "discoverable" => true,
            "published_at" => ~N[2025-01-01 00:00:00]
          },
          attrs
        )
      )

    item
  end

  defp authed_conn(raw_token) do
    build_conn() |> put_req_header("authorization", "Bearer #{raw_token}")
  end

  describe "totals" do
    test "returns X-Total-Count and a meta block with grand totals", %{raw_token: raw} do
      {_community, collection} = scope_fixture()
      create_published(collection, %{})
      create_published(collection, %{})
      create_published(scope_fixture() |> elem(1), %{})

      conn =
        authed_conn(raw)
        |> get(~p"/api/v1/items", %{
          collection_id: collection.id
        })

      assert conn.status == 200

      assert Integer.to_string(Enum.count(json_response(conn, 200)["data"])) ==
               get_resp_header(conn, "x-total-count") |> List.first()

      %{"meta" => meta} = json_response(conn, 200)
      assert meta["total_count"] == 2
      assert meta["total_pages"] == 1
      assert meta["page"] == 1
      assert meta["per_page"] == 20
    end

    test "clamps page and per_page", %{raw_token: raw} do
      {_community, collection} = scope_fixture()
      create_published(collection, %{})
      create_published(collection, %{})
      create_published(collection, %{})

      # per_page floor (0 → 20 default), page 99999 clamps to last page.
      conn =
        authed_conn(raw)
        |> get(~p"/api/v1/items", %{
          collection_id: collection.id,
          per_page: "0",
          page: "99999"
        })

      %{"meta" => meta, "data" => data} = json_response(conn, 200)
      assert data != []
      assert meta["page"] == 1
      assert meta["per_page"] == 20
    end

    test "invalid pagination values do not 500; invalid year 400s", %{raw_token: raw} do
      conn = authed_conn(raw) |> get(~p"/api/v1/items", year: "not-a-number")

      assert conn.status == 400
      assert %{"error" => "bad_request"} = json_response(conn, 400)
    end
  end

  describe "collection brief" do
    test "item briefs carry the owning collection", %{raw_token: raw} do
      {_community, collection} = scope_fixture()
      _item = create_published(collection, %{})

      conn = authed_conn(raw) |> get(~p"/api/v1/items", collection_id: collection.id)

      data = json_response(conn, 200)["data"]
      assert [%{"collection" => collection_brief} | _] = data
      assert collection_brief["id"] == collection.id
      assert collection_brief["name"] == collection.name
      assert collection_brief["handle"] == collection.handle
    end
  end

  describe "sorting and browsing" do
    setup do
      {community, collection} = scope_fixture()

      a =
        create_published(collection, %{
          "title" => "Algoritma Abc",
          "published_at" => ~N[2024-01-01 00:00:00]
        })

      b =
        create_published(collection, %{
          "title" => "Belajar Berhitung",
          "published_at" => ~N[2025-06-01 00:00:00]
        })

      c =
        create_published(collection, %{
          "title" => "Citizen Science",
          "published_at" => ~N[2023-01-01 00:00:00],
          "student_name" => "Andi",
          "subject_classification" => "Ekonomi Pembangunan"
        })

      %{community: community, collection: collection, items: [a, b, c]}
    end

    test "sort=title order=asc orders alphabetically", %{raw_token: raw, items: [a, b, c]} do
      conn =
        authed_conn(raw)
        |> get(~p"/api/v1/items", %{
          collection_id: a.collection_id,
          sort: "title",
          order: "asc",
          per_page: "10"
        })

      titles = Enum.map(json_response(conn, 200)["data"], & &1["title"])
      assert titles == [a.title, b.title, c.title]
    end

    test "sort=published_at order=desc orders newest first", %{raw_token: raw, items: [a, b, c]} do
      conn =
        authed_conn(raw)
        |> get(~p"/api/v1/items", %{
          collection_id: a.collection_id,
          sort: "published_at",
          order: "desc",
          per_page: "10"
        })

      titles = Enum.map(json_response(conn, 200)["data"], & &1["title"])
      assert titles == [b.title, a.title, c.title]
    end

    test "sort=author order=asc orders by author (nils last)", %{raw_token: raw, items: [a, b, c]} do
      conn =
        authed_conn(raw)
        |> get(~p"/api/v1/items", %{
          collection_id: a.collection_id,
          sort: "author",
          order: "asc",
          per_page: "10"
        })

      names = Enum.map(json_response(conn, 200)["data"], & &1["student_name"])
      assert names == ["Andi", nil, nil]
      assert b.title
      assert c.title
    end

    test "starts_with filters by title prefix", %{raw_token: raw, items: [_a, b, _c]} do
      conn =
        authed_conn(raw)
        |> get(~p"/api/v1/items", %{
          collection_id: b.collection_id,
          starts_with: "Be",
          per_page: "10"
        })

      titles = Enum.map(json_response(conn, 200)["data"], & &1["title"])
      assert titles == [b.title]
    end

    test "sort=subject starts_with filters by subject prefix", %{
      raw_token: raw,
      items: [_a, _b, c]
    } do
      conn =
        authed_conn(raw)
        |> get(~p"/api/v1/items", %{
          collection_id: c.collection_id,
          sort: "subject",
          starts_with: "Ek",
          per_page: "10"
        })

      titles = Enum.map(json_response(conn, 200)["data"], & &1["title"])
      assert titles == [c.title]
    end
  end
end
