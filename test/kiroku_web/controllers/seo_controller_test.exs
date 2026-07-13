defmodule KirokuWeb.SeoControllerTest do
  use KirokuWeb.ConnCase, async: true

  alias Kiroku.{Onboarding, Repository}

  # Onboarding state is cached in :persistent_term (global) and reflects the
  # seedless test DB. Force it complete so the SetupGuard plug doesn't redirect
  # crawler endpoints to /setup.
  setup do
    Onboarding.force_setup_state(true)
    :ok
  end

  defp create_collection(opts \\ []) do
    handle = "comm-#{System.unique_integer([:positive])}"

    {:ok, community} =
      Repository.create_community(%{"name" => "Community", "handle" => handle})

    base = %{
      "name" => "Collection",
      "community_id" => community.id,
      "handle" => "coll-#{System.unique_integer([:positive])}"
    }

    attrs =
      Enum.reduce(opts, base, fn {k, v}, acc -> Map.put(acc, to_string(k), v) end)

    {:ok, collection} = Repository.create_collection(attrs)
    collection
  end

  defp published_item(collection_id, attrs) do
    {:ok, item} =
      Repository.create_item(
        Map.merge(
          %{
            "title" => "Test Item",
            "collection_id" => collection_id,
            "status" => "published",
            "discoverable" => true,
            "access_level" => "open"
          },
          attrs
        )
      )

    item
  end

  describe "GET /robots.txt" do
    test "serves a crawlable robots.txt with a sitemap directive", %{conn: conn} do
      conn = get(conn, ~p"/robots.txt")

      body = response(conn, 200)
      assert conn |> get_resp_header("content-type") |> hd() =~ "text/plain"
      assert body =~ "User-agent: *"
      assert body =~ "Allow: /"
      assert body =~ "Sitemap: http://localhost:4000/sitemap.xml"
    end
  end

  describe "GET /sitemap.xml" do
    test "returns valid XML urlset", %{conn: conn} do
      conn = get(conn, ~p"/sitemap.xml")

      assert response_content_type(conn, :xml) =~ "application/xml"
      body = response(conn, 200)
      assert body =~ ~s(<?xml version="1.0")
      assert body =~ ~s(<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">)
      assert body =~ "</urlset>"
    end

    test "includes public items but excludes restricted ones", %{conn: conn} do
      collection = create_collection()
      open_item = published_item(collection.id, %{"title" => "Sitemap Open"})
      _restricted = published_item(collection.id, %{"access_level" => "restricted"})

      body = response(get(conn, ~p"/sitemap.xml"), 200)

      assert body =~ "/items/#{open_item.handle}</loc>"
      refute body =~ "restricted"
    end

    test "includes community and collection browse URLs", %{conn: conn} do
      collection = create_collection()

      body = response(get(conn, ~p"/sitemap.xml"), 200)

      assert body =~ "/communities/"
      assert body =~ "/collections/#{collection.handle}</loc>"
    end
  end
end
