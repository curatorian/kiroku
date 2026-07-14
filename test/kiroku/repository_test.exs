defmodule Kiroku.RepositoryTest do
  use Kiroku.DataCase, async: true

  alias Kiroku.Repository

  # ── Fixtures ───────────────────────────────────────────────────────────────

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
      Enum.reduce(opts, base, fn {k, v}, acc ->
        Map.put(acc, to_string(k), v)
      end)

    {:ok, collection} = Repository.create_collection(attrs)

    collection
  end

  defp create_item(attrs) do
    {:ok, item} =
      Repository.create_item(
        Map.merge(
          %{
            "title" => "Test Item",
            "collection_id" => create_collection().id
          },
          attrs
        )
      )

    item
  end

  defp reviewer, do: %Kiroku.Accounts.User{id: Ecto.UUID.generate(), user_type: :reviewer}
  defp admin, do: %Kiroku.Accounts.User{id: Ecto.UUID.generate(), user_type: :admin}

  # ── Valid transitions ──────────────────────────────────────────────────────

  describe "review FSM — valid transitions" do
    test "submit_item: draft → submitted" do
      item = create_item(%{"status" => "draft"})
      assert {:ok, updated} = Repository.submit_item(item)
      assert updated.status == :submitted
    end

    test "start_review: submitted → under_review" do
      r = reviewer()
      item = create_item(%{"status" => "submitted"})
      assert {:ok, updated} = Repository.start_review(item, r)
      assert updated.status == :under_review
      assert updated.reviewed_by_id == r.id
    end

    test "approve_item: under_review → published" do
      item = create_item(%{"status" => "under_review"})
      assert {:ok, updated} = Repository.approve_item(item, admin())
      assert updated.status == :published
      assert updated.discoverable == true
    end

    test "request_revision: under_review → submitted" do
      item = create_item(%{"status" => "under_review"})
      assert {:ok, updated} = Repository.request_revision(item, reviewer(), "Fix typo")
      assert updated.status == :submitted
      assert updated.review_note == "Fix typo"
    end

    test "reject_item: under_review → withdrawn" do
      item = create_item(%{"status" => "under_review"})
      assert {:ok, updated} = Repository.reject_item(item, admin(), "Plagiarism")
      assert updated.status == :withdrawn
      assert updated.discoverable == false
      assert updated.review_note == "Plagiarism"
    end

    test "withdraw_item_fsm: submitted → withdrawn" do
      item = create_item(%{"status" => "submitted"})
      assert {:ok, updated} = Repository.withdraw_item_fsm(item)
      assert updated.status == :withdrawn
      assert updated.discoverable == false
    end

    test "withdraw_item_fsm: published → withdrawn" do
      item = create_item(%{"status" => "published", "discoverable" => true})
      assert {:ok, updated} = Repository.withdraw_item_fsm(item)
      assert updated.status == :withdrawn
      assert updated.discoverable == false
    end
  end

  # ── Invalid transitions ────────────────────────────────────────────────────

  describe "review FSM — invalid transitions" do
    test "submit_item fails on non-draft" do
      item = create_item(%{"status" => "published"})
      assert {:error, :invalid_transition} = Repository.submit_item(item)
    end

    test "start_review fails on non-submitted" do
      item = create_item(%{"status" => "draft"})
      assert {:error, :invalid_transition} = Repository.start_review(item, reviewer())
    end

    test "approve_item fails on non-under_review" do
      item = create_item(%{"status" => "submitted"})
      assert {:error, :invalid_transition} = Repository.approve_item(item, admin())
    end

    test "request_revision fails on non-under_review" do
      item = create_item(%{"status" => "submitted"})
      assert {:error, :invalid_transition} = Repository.request_revision(item, reviewer(), "note")
    end

    test "reject_item fails on non-under_review" do
      item = create_item(%{"status" => "published"})
      assert {:error, :invalid_transition} = Repository.reject_item(item, admin(), "note")
    end

    test "withdraw_item_fsm fails on draft" do
      item = create_item(%{"status" => "draft"})
      assert {:error, :invalid_transition} = Repository.withdraw_item_fsm(item)
    end
  end

  # ── Full workflow sequence ─────────────────────────────────────────────────

  describe "review FSM — full workflow" do
    test "complete happy path: draft → submitted → under_review → published" do
      r = reviewer()
      a = admin()

      {:ok, item} =
        Repository.create_item(%{
          "title" => "Full Workflow Test",
          "collection_id" => create_collection().id,
          "status" => "draft"
        })

      {:ok, item} = Repository.submit_item(item)
      assert item.status == :submitted

      {:ok, item} = Repository.start_review(item, r)
      assert item.status == :under_review

      {:ok, item} = Repository.approve_item(item, a)
      assert item.status == :published
      assert item.discoverable == true
    end

    test "revision loop: under_review → submitted → under_review → published" do
      r = reviewer()
      a = admin()

      item = create_item(%{"status" => "under_review"})

      {:ok, item} = Repository.request_revision(item, r, "Needs more citations")
      assert item.status == :submitted

      {:ok, item} = Repository.start_review(item, r)
      assert item.status == :under_review

      {:ok, item} = Repository.approve_item(item, a)
      assert item.status == :published
    end
  end

  # ── Visibility scope in discovery ──────────────────────────────────────────

  describe "visibility scope filtering" do
    defp published_item(attrs) do
      create_item(
        Map.merge(
          %{"status" => "published", "discoverable" => true, "access_level" => "open"},
          attrs
        )
      )
    end

    test "public scope only sees :open items" do
      published_item(%{"title" => "Open One"})
      published_item(%{"title" => "Internal One", "access_level" => "internal"})
      published_item(%{"title" => "Restricted One", "access_level" => "restricted"})

      items = Repository.list_published_items(scope: :public)
      titles = Enum.map(items, & &1.title)

      assert "Open One" in titles
      refute "Internal One" in titles
      refute "Restricted One" in titles
    end

    test "internal scope sees :open and :internal items" do
      published_item(%{"title" => "Open Two"})
      published_item(%{"title" => "Internal Two", "access_level" => "internal"})
      published_item(%{"title" => "Restricted Two", "access_level" => "restricted"})

      items = Repository.list_published_items(scope: :internal)
      titles = Enum.map(items, & &1.title)

      assert "Open Two" in titles
      assert "Internal Two" in titles
      refute "Restricted Two" in titles
    end

    test "staff scope sees all published items" do
      published_item(%{"title" => "Open Three"})
      published_item(%{"title" => "Internal Three", "access_level" => "internal"})
      published_item(%{"title" => "Restricted Three", "access_level" => "restricted"})
      published_item(%{"title" => "Closed Three", "access_level" => "closed"})

      items = Repository.list_published_items(scope: :staff)
      titles = Enum.map(items, & &1.title)

      assert "Open Three" in titles
      assert "Internal Three" in titles
      assert "Restricted Three" in titles
      assert "Closed Three" in titles
    end

    test "search respects scope" do
      published_item(%{"title" => "Quantum Mechanics", "access_level" => "internal"})
      published_item(%{"title" => "Quantum Field Theory", "access_level" => "open"})

      public_results = Repository.search_items(%{term: "Quantum", scope: :public})
      internal_results = Repository.search_items(%{term: "Quantum", scope: :internal})

      assert Enum.count(public_results) == 1
      assert hd(public_results).title == "Quantum Field Theory"
      assert Enum.count(internal_results) == 2
    end

    test "search ranks by relevance (ts_rank) when a term is present" do
      # Both match "ekonomi". The first repeats the term far more often, so its
      # ts_rank is higher. It also has an OLDER published_at, so under a pure
      # newest-first ordering it would rank second — proving relevance wins.
      published_item(%{
        "title" => "Analisis Ekonomi Makro",
        "abstract" => String.duplicate("ekonomi ", 12),
        "published_at" => ~N[2020-01-01 00:00:00]
      })

      published_item(%{
        "title" => "Pengantar Ekonomi",
        "abstract" => "Sebuah pengantar singkat tentang ekonomi.",
        "published_at" => ~N[2024-01-01 00:00:00]
      })

      results = Repository.search_items(%{term: "ekonomi", scope: :public})

      assert Enum.map(results, & &1.title) == [
               "Analisis Ekonomi Makro",
               "Pengantar Ekonomi"
             ]
    end

    test "browse without a term still orders newest-first" do
      published_item(%{"title" => "Alpha", "published_at" => ~N[2020-01-01 00:00:00]})
      published_item(%{"title" => "Beta", "published_at" => ~N[2024-01-01 00:00:00]})

      results = Repository.list_published_items(scope: :public)
      titles = Enum.map(results, & &1.title)

      assert Enum.find_index(titles, &(&1 == "Beta")) <
               Enum.find_index(titles, &(&1 == "Alpha"))
    end
  end

  # ── Faceted search ──────────────────────────────────────────────────────────

  describe "facets/1" do
    setup do
      c = create_collection()

      [
        # 2024 skripsi in Hukum by Siti
        create_published_item_with(%{
          collection_id: c.id,
          title: "Analisis Hukum Pidana",
          item_type: "skripsi",
          faculty: "Hukum",
          publication_year: 2024,
          authors: ["Siti Aminah"],
          keywords: ["pidana", "hukum"]
        }),
        # 2024 skripsi in Hukum by Siti (different keyword)
        create_published_item_with(%{
          collection_id: c.id,
          title: "Studi Kasus Pidana",
          item_type: "skripsi",
          faculty: "Hukum",
          publication_year: 2024,
          authors: ["Siti Aminah"],
          keywords: ["pidana"]
        }),
        # 2023 tesis in Ekonomi by Budi
        create_published_item_with(%{
          collection_id: c.id,
          title: "Ekonomi Makro Indonesia",
          item_type: "tesis",
          faculty: "Ekonomi",
          publication_year: 2023,
          authors: ["Budi Santoso"],
          keywords: ["ekonomi"]
        })
      ]

      :ok
    end

    defp create_published_item_with(attrs) when is_map(attrs) do
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
        keyword_attrs = Enum.map(keywords, &%{keyword: &1})
        Repository.upsert_keywords_for_item(item.id, keyword_attrs)
      end

      item
    end

    test "returns counts per item_type" do
      facets = Repository.facets(%{scope: :public})

      types = Map.new(facets.item_types, &{&1.value, &1.count})
      assert types[:skripsi] == 2
      assert types[:tesis] == 1
    end

    test "returns counts per publication_year, newest first" do
      facets = Repository.facets(%{scope: :public})

      years = Enum.map(facets.years, & &1.value)
      assert years == [2024, 2023]
    end

    test "returns counts per faculty" do
      facets = Repository.facets(%{scope: :public})

      faculties = Map.new(facets.faculties, &{&1.value, &1.count})
      assert faculties["Hukum"] == 2
      assert faculties["Ekonomi"] == 1
    end

    test "returns author counts (distinct items, not per-keyword)" do
      facets = Repository.facets(%{scope: :public})

      authors = Map.new(facets.authors, &{&1.value, &1.count})
      assert authors["Siti Aminah"] == 2
      assert authors["Budi Santoso"] == 1
    end

    test "returns keyword counts" do
      facets = Repository.facets(%{scope: :public})

      keywords = Map.new(facets.keywords, &{&1.value, &1.count})
      assert keywords["pidana"] == 2
      assert keywords["ekonomi"] == 1
      assert keywords["hukum"] == 1
    end

    test "respects visibility scope" do
      # Create a restricted item; its facets shouldn't appear under :public.
      create_published_item_with(%{
        collection_id: create_collection().id,
        title: "Secret Item",
        item_type: "disertasi",
        faculty: "Tambang",
        publication_year: 2024,
        authors: ["Rahasia"],
        keywords: ["confidential"],
        access_level: "restricted"
      })

      public_facets = Repository.facets(%{scope: :public})
      staff_facets = Repository.facets(%{scope: :staff})

      public_types = Enum.map(public_facets.item_types, & &1.value)
      staff_types = Enum.map(staff_facets.item_types, & &1.value)

      refute :disertasi in public_types
      assert :disertasi in staff_types
    end

    test "multi-select: a facet's own filter is excluded from its counts" do
      # With item_type=skripsi selected, the item_type facet should still show
      # ALL types available within the unfiltered set, not collapse to skripsi.
      facets = Repository.facets(%{scope: :public, item_type: :skripsi})

      type_values = Enum.map(facets.item_types, & &1.value)
      assert :skripsi in type_values
      assert :tesis in type_values
    end

    test "year facet narrows when filtering by item_type" do
      # tesis is 2023 only; the year facet under item_type=tesis should show
      # only 2023.
      facets = Repository.facets(%{scope: :public, item_type: :tesis})

      years = Enum.map(facets.years, & &1.value)
      assert years == [2023]
    end

    test "author filter narrows the result set" do
      results = Repository.search_items(%{scope: :public, author: "Siti"})
      titles = Enum.map(results, & &1.title)
      assert "Analisis Hukum Pidana" in titles
      assert "Studi Kasus Pidana" in titles
      refute "Ekonomi Makro Indonesia" in titles
    end

    test "keyword filter narrows the result set" do
      results = Repository.search_items(%{scope: :public, keyword: "pidana"})
      assert Enum.count(results) == 2
    end

    test "respects facet_limit option" do
      facets = Repository.facets(%{scope: :public, facet_limit: 1})

      # Each facet capped at 1 entry.
      assert length(facets.item_types) <= 1
      assert length(facets.keywords) <= 1
    end
  end

  # ── Browse-by-* aggregations ────────────────────────────────────────────────

  describe "browse_by_author/1" do
    setup do
      c = create_collection()

      create_published_item(%{
        collection_id: c.id,
        title: "Item A",
        authors: ["Budi Santoso", "Siti Aminah"]
      })

      create_published_item(%{
        collection_id: c.id,
        title: "Item B",
        authors: ["Budi Santoso"]
      })

      create_published_item(%{
        collection_id: c.id,
        title: "Restricted Item",
        authors: ["Rahasia"],
        access_level: "restricted"
      })

      :ok
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

    test "aggregates distinct item counts per author, alphabetical" do
      results = Repository.browse_by_author(scope: :public)

      names = Enum.map(results, & &1.value)
      assert names == ["Budi Santoso", "Siti Aminah"]

      counts = Map.new(results, &{&1.value, &1.count})
      assert counts["Budi Santoso"] == 2
      assert counts["Siti Aminah"] == 1
    end

    test "respects visibility scope" do
      public_results = Repository.browse_by_author(scope: :public)
      staff_results = Repository.browse_by_author(scope: :staff)

      public_names = Enum.map(public_results, & &1.value)
      staff_names = Enum.map(staff_results, & &1.value)

      refute "Rahasia" in public_names
      assert "Rahasia" in staff_names
    end

    test "respects limit option" do
      results = Repository.browse_by_author(scope: :public, limit: 1)
      assert length(results) == 1
    end
  end

  describe "browse_by_date/1" do
    setup do
      c = create_collection()

      [
        %{"title" => "Old", "publication_year" => 2020},
        %{"title" => "New", "publication_year" => 2024},
        %{"title" => "Mid", "publication_year" => 2022},
        %{"title" => "Untimed"}
      ]
      |> Enum.each(fn attrs ->
        create_item(Map.merge(%{"collection_id" => c.id, "status" => "published"}, attrs))
      end)

      :ok
    end

    test "groups by publication_year, newest first" do
      results = Repository.browse_by_date(scope: :public)

      years = Enum.map(results, & &1.value)
      assert years == [2024, 2022, 2020]
    end

    test "excludes items without a publication_year" do
      results = Repository.browse_by_date(scope: :public)
      # Only 3 of the 4 items have publication_year set.
      assert Enum.map(results, & &1.count) |> Enum.sum() == 3
    end
  end

  describe "browse_by_title/1" do
    setup do
      c = create_collection()

      ["Cherry", "Apple", "Banana"]
      |> Enum.each(fn title ->
        create_item(%{
          "collection_id" => c.id,
          "title" => title,
          "status" => "published",
          "discoverable" => true,
          "access_level" => "open"
        })
      end)

      :ok
    end

    test "returns items alphabetical by title" do
      {items, _pagination} = Repository.browse_by_title(scope: :public)
      titles = Enum.map(items, & &1.title)
      assert titles == ["Apple", "Banana", "Cherry"]
    end

    test "paginates" do
      {items, pagination} = Repository.browse_by_title(scope: :public, page: 1, per_page: 2)
      assert length(items) == 2
      assert pagination.total_count == 3
      assert pagination.total_pages == 2

      {items2, _} = Repository.browse_by_title(scope: :public, page: 2, per_page: 2)
      assert length(items2) == 1
    end
  end

  # ── import_item upsert id regression ────────────────────────────────────────

  describe "import_item/1 — upsert returns the actual persisted id" do
    # Regression: Ecto's on_conflict returns a struct with a freshly-generated
    # (never-persisted) id when the conflict target matches, unless
    # returning: true is set. Callers that rely on item.id after an upsert
    # (the MSSQL importer creates bitstreams with it) would hit FK constraint
    # failures. See lib/kiroku/repository.ex:import_item/1.

    test "on insert: returns the newly-created id" do
      collection = create_collection()

      attrs = %{
        "title" => "First Import",
        "collection_id" => collection.id,
        "legacy_id" => "skripsi/12345",
        "handle" => "imp-#{System.unique_integer([:positive])}"
      }

      assert {:ok, item} = Repository.import_item(attrs)
      assert item.id != nil

      # The returned id must be the one actually persisted.
      assert Repo.get(Kiroku.Repository.Item, item.id) != nil
    end

    test "on update (conflict on legacy_id): returns the EXISTING id, not a phantom" do
      collection = create_collection()
      handle = "imp-#{System.unique_integer([:positive])}"

      {:ok, original} =
        Repository.import_item(%{
          "title" => "Original Title",
          "collection_id" => collection.id,
          "legacy_id" => "skripsi/99999",
          "handle" => handle
        })

      # Re-import the same legacy_id with updated fields.
      {:ok, updated} =
        Repository.import_item(%{
          "title" => "Updated Title",
          "collection_id" => collection.id,
          "legacy_id" => "skripsi/99999",
          "handle" => handle
        })

      # The returned id must match the original persisted row — otherwise
      # callers creating child records (bitstreams, authors, keywords) would
      # pass a phantom id that triggers FK constraint failures.
      assert updated.id == original.id

      # And it must be findable in the DB.
      assert Repo.get(Kiroku.Repository.Item, updated.id) != nil
      assert Repo.get!(Kiroku.Repository.Item, updated.id).title == "Updated Title"
    end

    test "the returned id is usable for child-record inserts (the FK bug)" do
      collection = create_collection()
      handle = "imp-#{System.unique_integer([:positive])}"

      # First import creates the row.
      {:ok, _original} =
        Repository.import_item(%{
          "title" => "V1",
          "collection_id" => collection.id,
          "legacy_id" => "skripsi/77777",
          "handle" => handle
        })

      # Second import (conflict path) returns an id. If the bug were present,
      # the bitstream insert below would fail with an FK constraint error.
      {:ok, updated} =
        Repository.import_item(%{
          "title" => "V2",
          "collection_id" => collection.id,
          "legacy_id" => "skripsi/77777",
          "handle" => handle
        })

      assert {:ok, _bitstream} =
               Kiroku.Content.create_bitstream(%{
                 "item_id" => updated.id,
                 "filename" => "chapter1.pdf",
                 "bundle_name" => "CHAPTER",
                 "sequence" => 1,
                 "storage_type" => "url",
                 "storage_url" => "https://example.com/ch1.pdf",
                 "access_level" => "inherit"
               })
    end
  end

  describe "collection default_item_access_level inheritance" do
    test "new item inherits collection default when access_level not specified" do
      collection = create_collection(default_item_access_level: "internal")

      {:ok, item} =
        Repository.create_item(%{"title" => "Inherited Item", "collection_id" => collection.id})

      assert item.access_level == :internal
    end

    test "explicit access_level overrides collection default" do
      collection = create_collection(default_item_access_level: "internal")

      {:ok, item} =
        Repository.create_item(%{
          "title" => "Explicit Item",
          "collection_id" => collection.id,
          "access_level" => "open"
        })

      assert item.access_level == :open
    end
  end

  # ── Community & Collection browse visibility ───────────────────────────────

  describe "community browse visibility" do
    defp create_community(attrs) do
      handle = "comm-#{System.unique_integer([:positive])}"

      {:ok, community} =
        Repository.create_community(
          Map.merge(%{"name" => "Community", "handle" => handle}, attrs)
        )

      community
    end

    test "public scope hides non-open communities" do
      create_community(%{"name" => "Open C", "access_level" => "open"})
      create_community(%{"name" => "Internal C", "access_level" => "internal"})
      create_community(%{"name" => "Restricted C", "access_level" => "restricted"})

      names = Repository.list_communities(scope: :public) |> Enum.map(& &1.name)

      assert "Open C" in names
      refute "Internal C" in names
      refute "Restricted C" in names
    end

    test "internal scope sees open and internal communities" do
      create_community(%{"name" => "Open R", "access_level" => "open"})
      create_community(%{"name" => "Internal R", "access_level" => "internal"})
      create_community(%{"name" => "Restricted R", "access_level" => "restricted"})

      names = Repository.list_communities(scope: :internal) |> Enum.map(& &1.name)

      assert "Open R" in names
      assert "Internal R" in names
      refute "Restricted R" in names
    end

    test "staff scope sees all active communities" do
      create_community(%{"name" => "Closed S", "access_level" => "closed"})

      names = Repository.list_communities(scope: :staff) |> Enum.map(& &1.name)

      assert "Closed S" in names
    end
  end

  describe "collection browse visibility" do
    test "public scope hides non-open collections" do
      community = create_community(%{"access_level" => "open"})

      {:ok, _} =
        Repository.create_collection(%{
          "name" => "Open Coll",
          "community_id" => community.id,
          "handle" => "coll-#{System.unique_integer([:positive])}",
          "access_level" => "open"
        })

      {:ok, _} =
        Repository.create_collection(%{
          "name" => "Internal Coll",
          "community_id" => community.id,
          "handle" => "coll-#{System.unique_integer([:positive])}",
          "access_level" => "internal"
        })

      names =
        Repository.list_collections_for_community(community.id, scope: :public)
        |> Enum.map(& &1.name)

      assert "Open Coll" in names
      refute "Internal Coll" in names

      internal_names =
        Repository.list_collections_for_community(community.id, scope: :internal)
        |> Enum.map(& &1.name)

      assert "Internal Coll" in internal_names
    end
  end
end
