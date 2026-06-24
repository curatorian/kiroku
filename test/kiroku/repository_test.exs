defmodule Kiroku.RepositoryTest do
  use Kiroku.DataCase, async: true

  alias Kiroku.Repository

  # ── Fixtures ───────────────────────────────────────────────────────────────

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
end
