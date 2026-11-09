defmodule KirokuWeb.SeoDiscoverabilityTest do
  use KirokuWeb.ConnCase, async: true

  alias Kiroku.Content
  alias Kiroku.Onboarding
  alias Kiroku.Repository

  # Onboarding state is cached in :persistent_term (global) and reflects the
  # seedless test DB. Force it complete so the SetupGuard plug doesn't redirect
  # pages to /setup.
  setup do
    Onboarding.force_setup_state(true)
    :ok
  end

  defp create_collection do
    handle = "comm-#{System.unique_integer([:positive])}"

    {:ok, community} =
      Repository.create_community(%{"name" => "Community", "handle" => handle})

    {:ok, collection} =
      Repository.create_collection(%{
        "name" => "Collection",
        "community_id" => community.id,
        "handle" => "coll-#{System.unique_integer([:positive])}"
      })

    collection
  end

  defp create_item(collection_id, attrs \\ %{}) do
    {:ok, item} =
      Repository.create_item(
        Map.merge(
          %{
            "title" => "Discoverability Item",
            "handle" => "disc-#{System.unique_integer([:positive])}",
            "abstract" => "An abstract used as the meta description.",
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

  defp local_bitstream(item, opts \\ %{}) do
    path = "seo-test/#{Ecto.UUID.generate()}.pdf"
    full = Path.join("priv/uploads", path)
    File.mkdir_p!(Path.dirname(full))
    File.write!(full, "%PDF-1.4 fake bytes")

    {:ok, bs} =
      Content.create_bitstream(
        Map.merge(
          %{
            item_id: item.id,
            filename: "thesis.pdf",
            bundle_name: :ORIGINAL,
            sequence: 1,
            storage_type: :local,
            storage_path: path,
            mime_type: "application/pdf",
            access_level: :open
          },
          opts
        )
      )

    bs
  end

  # ── robots.txt ────────────────────────────────────────────────────────────────

  test "robots.txt keeps the OAI-PMH endpoint crawlable", %{conn: conn} do
    body = response(get(conn, ~p"/robots.txt"), 200)

    assert body =~ "Disallow: /api/"
    assert body =~ "Allow: /api/oai"
  end

  # ── Item detail page: 404 / tombstone / public ───────────────────────────────

  test "unknown item handle raises a real 404 (rendered as 404 page in prod)", %{conn: conn} do
    # Phoenix renders the 404 error page via Plug.Exception, then re-raises
    # after the response is sent — assert_raise is the idiomatic test.
    assert_raise Ecto.NoResultsError, fn ->
      get(conn, ~p"/items/no-such-handle-#{System.unique_integer([:positive])}")
    end
  end

  test "withdrawn item renders a tombstone with noindex and no metadata", %{conn: conn} do
    collection = create_collection()

    item =
      create_item(collection.id, %{
        "title" => "Withdrawn Secret Title",
        "status" => "withdrawn",
        "discoverable" => false
      })

    body = response(get(conn, ~p"/items/#{item.handle}"), 200)

    assert body =~ ~s(id="item-tombstone")
    assert body =~ "Item withdrawn"
    # Keep it out of the index…
    assert body =~ ~s(name="robots" content="noindex, follow")
    # …and leak no metadata.
    refute body =~ "Withdrawn Secret Title"
    refute body =~ "citation_title"
  end

  test "draft item renders an unpublished tombstone for anonymous visitors", %{conn: conn} do
    collection = create_collection()

    item =
      create_item(collection.id, %{
        "title" => "Draft Secret Title",
        "status" => "draft"
      })

    body = response(get(conn, ~p"/items/#{item.handle}"), 200)

    assert body =~ ~s(id="item-tombstone")
    assert body =~ "Item not yet published"
    assert body =~ ~s(name="robots" content="noindex, follow")
    refute body =~ "Draft Secret Title"
  end

  test "non-open published item renders a restricted tombstone", %{conn: conn} do
    collection = create_collection()

    item =
      create_item(collection.id, %{
        "title" => "Internal Secret Title",
        "access_level" => "internal"
      })

    body = response(get(conn, ~p"/items/#{item.handle}"), 200)

    assert body =~ ~s(id="item-tombstone")
    assert body =~ "Item restricted"
    assert body =~ ~s(name="robots" content="noindex, follow")
    refute body =~ "Internal Secret Title"
  end

  test "public item page is indexable with canonical and structured data", %{conn: conn} do
    collection = create_collection()
    item = create_item(collection.id, %{"title" => "Public Findable Work"})

    body = response(get(conn, ~p"/items/#{item.handle}"), 200)

    refute body =~ ~s(id="item-tombstone")
    refute body =~ ~s(name="robots")
    assert body =~ ~s(<link rel="canonical" href="http://localhost:4000/items/#{item.handle}")
    assert body =~ ~s(name="citation_title")
    assert body =~ ~s(@type": "BreadcrumbList")
  end

  # ── Bitstream access (file leak fix) ─────────────────────────────────────────

  test "files of a draft item are not served to anonymous visitors", %{conn: conn} do
    collection = create_collection()
    item = create_item(collection.id, %{"status" => "draft"})
    bs = local_bitstream(item)

    conn = get(conn, ~p"/items/#{item.handle}/bitstreams/#{bs.id}")

    assert response(conn, 403)
  end

  test "files of a withdrawn item are not served to anonymous visitors", %{conn: conn} do
    collection = create_collection()

    item =
      create_item(collection.id, %{"status" => "withdrawn", "discoverable" => false})

    bs = local_bitstream(item)

    conn = get(conn, ~p"/items/#{item.handle}/bitstreams/#{bs.id}")

    assert response(conn, 403)
  end

  test "open files of a public item remain downloadable", %{conn: conn} do
    collection = create_collection()
    item = create_item(collection.id)
    bs = local_bitstream(item)

    conn = get(conn, ~p"/items/#{item.handle}/bitstreams/#{bs.id}")

    assert response(conn, 200) =~ "fake bytes"
  end

  # ── Search: noindex + canonical ──────────────────────────────────────────────

  test "search page is noindex with a canonical to the bare URL", %{conn: conn} do
    body = response(get(conn, ~p"/search?q=pembelajaran&year=2024&locale=en"), 200)

    assert body =~ ~s(name="robots" content="noindex, follow")
    assert body =~ ~s(<link rel="canonical" href="http://localhost:4000/search")
  end

  # ── Legacy handle resolver: 301 ──────────────────────────────────────────────

  test "legacy /handle URLs answer with a permanent redirect", %{conn: conn} do
    collection = create_collection()
    item = create_item(collection.id)

    conn = get(conn, ~p"/handle/#{item.handle}")

    assert redirected_to(conn, 301) == ~p"/items/#{item.handle}"
  end

  # ── Home page ────────────────────────────────────────────────────────────────

  test "home page has a branded title, description, and canonical", %{conn: conn} do
    body = response(get(conn, ~p"/"), 200)

    assert body =~ ~s(<title data-default="Kiroku")
    assert body =~ "Institutional Repository</title>"
    assert body =~ ~s(<link rel="canonical" href="http://localhost:4000/">)
    assert body =~ ~s(name="description")
  end
end
