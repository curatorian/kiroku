defmodule Kiroku.ContentTest do
  use Kiroku.DataCase, async: true

  alias Kiroku.{Content, Repository}
  alias Kiroku.Repository.Item

  # ── Fixtures ───────────────────────────────────────────────────────────────

  defp create_item(attrs \\ %{}) do
    {:ok, item} =
      Repository.create_item(
        Map.merge(
          %{
            "title" => "Test Thesis",
            "collection_id" => create_collection().id,
            "status" => "published",
            "discoverable" => true,
            "access_level" => "open"
          },
          attrs
        )
      )

    item
  end

  defp create_collection do
    handle = "test-comm-#{System.unique_integer([:positive])}"

    {:ok, community} =
      Repository.create_community(%{"name" => "Test Community", "handle" => handle})

    {:ok, collection} =
      Repository.create_collection(%{
        "name" => "Test Collection",
        "community_id" => community.id,
        "handle" => "test-coll-#{System.unique_integer([:positive])}"
      })

    collection
  end

  defp create_bitstream(item, attrs) do
    {:ok, bitstream} =
      Content.create_bitstream(
        Map.merge(
          %{
            "item_id" => item.id,
            "filename" => "test.pdf",
            "bundle_name" => "ORIGINAL",
            "sequence" => 1,
            "storage_type" => "local",
            "access_level" => "open"
          },
          attrs
        )
      )

    bitstream
  end

  defp staff_user, do: %{user_type: :admin}
  defp regular_user, do: %{user_type: :submitter}
  defp anonymous, do: nil

  # ── Bundle-level rules ─────────────────────────────────────────────────────

  describe "accessible?/3 — THUMBNAIL bundle" do
    test "always accessible to everyone" do
      item = create_item()
      bs = create_bitstream(item, %{"bundle_name" => "THUMBNAIL", "access_level" => "open"})

      assert Content.accessible?(bs, anonymous(), item)
      assert Content.accessible?(bs, regular_user(), item)
      assert Content.accessible?(bs, staff_user(), item)
    end
  end

  describe "accessible?/3 — ADMINISTRATIVE bundle" do
    test "only staff can access" do
      item = create_item()
      bs = create_bitstream(item, %{"bundle_name" => "ADMINISTRATIVE", "sequence" => 1})

      refute Content.accessible?(bs, anonymous(), item)
      refute Content.accessible?(bs, regular_user(), item)
      assert Content.accessible?(bs, staff_user(), item)
    end
  end

  describe "accessible?/3 — LICENSE bundle" do
    test "only staff can access" do
      item = create_item()
      bs = create_bitstream(item, %{"bundle_name" => "LICENSE", "sequence" => 1})

      refute Content.accessible?(bs, anonymous(), item)
      assert Content.accessible?(bs, staff_user(), item)
    end
  end

  # ── Abstract (ORIGINAL seq 1) ──────────────────────────────────────────────

  describe "accessible?/3 — abstract PDF (ORIGINAL sequence 1)" do
    test "accessible to everyone when open, even under embargo" do
      future = Date.add(Date.utc_today(), 30)

      item =
        create_item(%{
          "embargo_open_date" => Date.to_iso8601(future),
          "status" => "embargoed"
        })

      bs = create_bitstream(item, %{"bundle_name" => "ORIGINAL", "sequence" => 1, "access_level" => "open"})

      assert Item.files_embargoed?(item)
      assert Content.accessible?(bs, anonymous(), item)
      assert Content.accessible?(bs, regular_user(), item)
    end

    test "respects access_level even though embargo-exempt" do
      item = create_item()
      bs = create_bitstream(item, %{"bundle_name" => "ORIGINAL", "sequence" => 1, "access_level" => "restricted"})

      refute Content.accessible?(bs, anonymous(), item)
      assert Content.accessible?(bs, staff_user(), item)
    end
  end

  # ── Embargo ────────────────────────────────────────────────────────────────

  describe "accessible?/3 — embargoed items" do
    test "non-abstract files blocked for anonymous and regular users" do
      future = Date.add(Date.utc_today(), 30)

      item =
        create_item(%{
          "embargo_open_date" => Date.to_iso8601(future),
          "status" => "embargoed"
        })

      bs = create_bitstream(item, %{"bundle_name" => "ORIGINAL", "sequence" => 2, "access_level" => "open"})

      assert Item.files_embargoed?(item)
      refute Content.accessible?(bs, anonymous(), item)
      refute Content.accessible?(bs, regular_user(), item)
    end

    test "staff can access embargoed files" do
      future = Date.add(Date.utc_today(), 30)

      item =
        create_item(%{
          "embargo_open_date" => Date.to_iso8601(future),
          "status" => "embargoed"
        })

      bs = create_bitstream(item, %{"bundle_name" => "ORIGINAL", "sequence" => 2, "access_level" => "open"})

      assert Content.accessible?(bs, staff_user(), item)
    end
  end

  # ── Per-bitstream access_level ─────────────────────────────────────────────

  describe "accessible?/3 — per-bitstream access_level" do
    test ":open accessible to all" do
      item = create_item()
      bs = create_bitstream(item, %{"sequence" => 2, "access_level" => "open"})

      assert Content.accessible?(bs, anonymous(), item)
      assert Content.accessible?(bs, regular_user(), item)
    end

    test ":restricted only staff" do
      item = create_item()
      bs = create_bitstream(item, %{"sequence" => 2, "access_level" => "restricted"})

      refute Content.accessible?(bs, anonymous(), item)
      refute Content.accessible?(bs, regular_user(), item)
      assert Content.accessible?(bs, staff_user(), item)
    end

    test ":closed blocks everyone except staff" do
      item = create_item()
      bs = create_bitstream(item, %{"sequence" => 2, "access_level" => "closed"})

      refute Content.accessible?(bs, anonymous(), item)
      refute Content.accessible?(bs, regular_user(), item)
      assert Content.accessible?(bs, staff_user(), item)
    end

    test ":inherit resolves to item access_level" do
      item = create_item(%{"access_level" => "open"})
      bs = create_bitstream(item, %{"sequence" => 2, "access_level" => "inherit"})

      assert Content.accessible?(bs, anonymous(), item)

      item2 = create_item(%{"access_level" => "restricted"})
      bs2 = create_bitstream(item2, %{"sequence" => 2, "access_level" => "inherit"})

      refute Content.accessible?(bs2, anonymous(), item2)
      assert Content.accessible?(bs2, staff_user(), item2)
    end
  end

  # ── files_embargoed? ───────────────────────────────────────────────────────

  describe "files_embargoed?/1" do
    test "false when no embargo dates" do
      item = create_item()
      refute Item.files_embargoed?(item)
    end

    test "true when embargo_open_date is in the future" do
      future = Date.add(Date.utc_today(), 30)
      item = create_item(%{"embargo_open_date" => Date.to_iso8601(future), "status" => "embargoed"})
      assert Item.files_embargoed?(item)
    end

    test "false when embargo_open_date has passed" do
      past = Date.add(Date.utc_today(), -30)
      item = create_item(%{"embargo_open_date" => Date.to_iso8601(past)})
      refute Item.files_embargoed?(item)
    end
  end
end
