defmodule KirokuWeb.ItemSeoComponentTest do
  use KirokuWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Kiroku.Repository

  # Rendering the SEO component directly (not through the browser/LiveView
  # pipeline) keeps these tests deterministic — they don't depend on the
  # SetupGuard plug or the global onboarding cache.

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

  defp item_with_authors do
    {:ok, item} =
      Repository.create_item(%{
        "title" => "Analisis Pembelajaran Matematika",
        "handle" => "seo-test-#{System.unique_integer([:positive])}",
        "abstract" => "Studi tentang metode pembelajaran matematika modern.",
        "collection_id" => create_collection().id,
        "status" => "published",
        "discoverable" => true,
        "access_level" => "open",
        "item_type" => "skripsi",
        "publication_year" => 2024,
        "doi" => "10.1234/test.5678"
      })

    {:ok, _} =
      Repository.create_item_author(%{
        "item_id" => item.id,
        "author_name" => "Siti Rahma",
        "orcid" => "0000-0002-1234-5678",
        "sequence" => 1
      })

    {:ok, _} =
      Repository.create_item_author(%{
        "item_id" => item.id,
        "author_name" => "Budi Santoso",
        "sequence" => 2
      })

    Repository.get_item_with_preloads!(item.handle)
  end

  describe "SEO.item_meta/1" do
    test "renders Google Scholar citation_* tags" do
      item = item_with_authors()

      html = render_component(&KirokuWeb.SEO.item_meta/1, %{item: item, bitstreams: []})

      assert html =~ ~s(name="citation_title")
      assert html =~ ~s(name="citation_author")
      assert html =~ "Siti Rahma"
      assert html =~ "Budi Santoso"
      assert html =~ ~s(name="citation_publication_date")
      assert html =~ ~s(name="citation_doi")
      assert html =~ "10.1234/test.5678"
    end

    test "renders Open Graph and Twitter Card tags" do
      item = item_with_authors()

      html = render_component(&KirokuWeb.SEO.item_meta/1, %{item: item, bitstreams: []})

      assert html =~ ~s(property="og:title")
      assert html =~ ~s(property="og:type" content="article")
      assert html =~ ~s(property="og:locale" content="id_ID")
      assert html =~ ~s(name="twitter:card")
    end

    test "renders Schema.org JSON-LD with type and ORCID" do
      item = item_with_authors()

      html = render_component(&KirokuWeb.SEO.item_meta/1, %{item: item, bitstreams: []})

      assert html =~ ~s(type="application/ld+json")
      assert html =~ "schema.org"
      # Thesis types (skripsi) map to "Thesis".
      assert html =~ ~s("@type": "Thesis")
      # ORCID surfaces as an @id in the author node.
      assert html =~ "orcid.org/0000-0002-1234-5678"
    end

    test "journal item types map to ScholarlyArticle" do
      {:ok, item} =
        Repository.create_item(%{
          "title" => "A Journal Article",
          "handle" => "seo-jrn-#{System.unique_integer([:positive])}",
          "collection_id" => create_collection().id,
          "status" => "published",
          "discoverable" => true,
          "access_level" => "open",
          "item_type" => "jurnal_nasional"
        })

      html =
        render_component(&KirokuWeb.SEO.item_meta/1, %{
          item: Repository.get_item_with_preloads!(item.handle),
          bitstreams: []
        })

      assert html =~ ~s("@type": "ScholarlyArticle")
    end
  end
end
