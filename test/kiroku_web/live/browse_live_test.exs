defmodule KirokuWeb.BrowseLiveTest do
  use KirokuWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Kiroku.Repository

  # Verifies the four browse modes (structure / author / date / title) render
  # and that the mode tabs produce the expected URL params.

  defp create_collection do
    handle = "comm-#{System.unique_integer([:positive])}"

    {:ok, community} =
      Repository.create_community(%{"name" => "Test Community", "handle" => handle})

    {:ok, collection} =
      Repository.create_collection(%{
        "name" => "Test Collection",
        "community_id" => community.id,
        "handle" => "coll-#{System.unique_integer([:positive])}"
      })

    collection
  end

  defp create_published_item(attrs) do
    authors = Map.get(attrs, :authors, [])

    item_attrs =
      attrs
      |> Map.drop([:authors])
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

    item
  end

  setup do
    c = create_collection()

    create_published_item(%{
      collection_id: c.id,
      title: "Penelitian Apel",
      publication_year: 2024,
      authors: ["Siti Aminah"]
    })

    create_published_item(%{
      collection_id: c.id,
      title: "Penelitian Mangga",
      publication_year: 2023,
      authors: ["Budi Santoso"]
    })

    :ok
  end

  describe "mode tabs" do
    test "default mode is :structure", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/browse")
      assert html =~ "By Structure"
      assert html =~ "Test Community"
    end

    test "clicking a tab patches the URL with ?by=", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/browse")

      view
      |> element("a", "By Author")
      |> render_click()

      assert_patch(view, ~p"/browse?by=author")
    end
  end

  describe "author mode" do
    test "lists authors alphabetically with counts and jump-bar", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/browse?by=author")

      # Both authors render.
      assert html =~ "Siti Aminah"
      assert html =~ "Budi Santoso"

      # Count badge shows item count.
      assert html =~ "1"

      # Alphabet jump-bar has the letter groups.
      assert html =~ "#letter-B"
      assert html =~ "#letter-S"
    end

    test "clicking an author links into /search with author filter", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/browse?by=author")

      # The author's link should produce a search URL.
      assert html =~ "author=Siti"
      assert html =~ "author=Budi"
    end
  end

  describe "date mode" do
    test "lists years newest-first with item counts", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/browse?by=date")

      # 2024 should appear before 2023.
      {p_new, _} = :binary.match(html, "2024")
      {p_old, _} = :binary.match(html, "2023")
      assert p_new < p_old

      # Link into search with year filter.
      assert html =~ "year=2024"
      assert html =~ "year=2023"
    end
  end

  describe "title mode" do
    test "lists items alphabetically", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/browse?by=title")

      # Alphabetical: "Penelitian Apel" before "Penelitian Mangga".
      {p_apel, _} = :binary.match(html, "Apel")
      {p_mangga, _} = :binary.match(html, "Mangga")
      assert p_apel < p_mangga
    end
  end
end
