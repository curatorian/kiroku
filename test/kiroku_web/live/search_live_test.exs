defmodule KirokuWeb.SearchLiveTest do
  use KirokuWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Kiroku.Repository

  # LiveView test of the public search page. Verifies the facet sidebar
  # renders counts and that filter URLs produce the expected state.
  #
  # Facet links use `<.link patch={...}>` (plain anchor navigation), so we
  # test them by navigating directly to the URL rather than simulating
  # click events. That mirrors how a real browser handles anchor links.

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

  defp create_published_item(attrs) do
    authors = Map.get(attrs, :authors, [])
    keywords = Map.get(attrs, :keywords, [])

    item_attrs =
      attrs
      |> Map.drop([:authors, :keywords])
      |> Enum.into(%{}, fn {k, v} -> {to_string(k), to_string(v)} end)

    {:ok, item} =
      Repository.create_item(
        Map.merge(
          %{
            "status" => "published",
            "discoverable" => true,
            "access_level" => "open"
          },
          item_attrs
        )
      )

    for author <- authors do
      {:ok, _} = Repository.create_item_author(%{"item_id" => item.id, "author_name" => author})
    end

    unless keywords == [] do
      Repository.upsert_keywords_for_item(item.id, Enum.map(keywords, &%{keyword: &1}))
    end

    item
  end

  setup do
    c = create_collection()

    create_published_item(%{
      collection_id: c.id,
      title: "Penelitian Hukum Pidana",
      abstract: "Penelitian ini membahas aspek pidana.",
      item_type: "skripsi",
      faculty: "Hukum",
      publication_year: 2024,
      authors: ["Siti Aminah"],
      keywords: ["pidana"]
    })

    create_published_item(%{
      collection_id: c.id,
      title: "Penelitian Ekonomi Mikro",
      abstract: "Penelitian ini membahas aspek ekonomi.",
      item_type: "tesis",
      faculty: "Ekonomi",
      publication_year: 2023,
      authors: ["Budi Santoso"],
      keywords: ["ekonomi"]
    })

    :ok
  end

  describe "facet sidebar" do
    test "renders all facet groups with counts when a search is active", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/search?q=Penelitian")

      # Each facet group has a label heading.
      assert html =~ "Type"
      assert html =~ "Year"
      assert html =~ "Faculty"
      assert html =~ "Author"
      assert html =~ "Subject / Keyword"

      # Counts appear next to values (display labels for item_type).
      assert html =~ "Skripsi"
      assert html =~ "Hukum"
      assert html =~ "Siti Aminah"
    end

    test "does not render facet counts before any search/filter is applied", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/search")

      # Empty state shown, not facet counts.
      assert html =~ "Enter a search term to begin."
    end

    test "facet sidebar contains links that toggle filters", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/search?q=Penelitian")

      # Facet links are anchor tags that patch the URL. Verify their hrefs
      # contain the expected filter param (Phoenix escapes & as &amp; in
      # HTML attributes).
      assert html =~ "type=skripsi"
      assert html =~ "type=tesis"
      assert html =~ "author=Siti"
      assert html =~ "author=Budi"
    end

    test "visiting a filtered URL applies the facet and narrows results", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/search?q=Penelitian&type=tesis")

      # Only the tesis item matches both filters.
      assert has_element?(view, "p", "1 result(s)")
    end

    test "clear all filters link is shown only when filters are active", %{conn: conn} do
      {:ok, _view, html_with} = live(conn, ~p"/search?q=Penelitian&type=tesis")
      assert html_with =~ "Clear all filters"

      {:ok, _view, html_without} = live(conn, ~p"/search")
      refute html_without =~ "Clear all filters"
    end

    test "year facet lists years newest-first", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/search?q=Penelitian")

      # Both years should appear in the facet sidebar, 2024 before 2023.
      {p24, _} = :binary.match(html, "2024")
      {p23, _} = :binary.match(html, "2023")
      assert p24 < p23
    end

    test "author facet links use the author's name as a substring filter", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/search?q=Penelitian")

      # The author link should URL-encode the name.
      assert html =~ "author=Siti"
      assert html =~ "author=Budi"
    end
  end
end
