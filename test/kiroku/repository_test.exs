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
  end

  # ── Collection default access inheritance ──────────────────────────────────

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
