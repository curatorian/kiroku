defmodule Kiroku.DoiTest do
  use Kiroku.DataCase, async: true

  # NOTE: Oban is configured with `testing: :inline` in config/test.exs, so
  # `Oban.insert/1` runs the worker synchronously in the calling process.
  # Integration tests therefore assert on side effects (item.doi, doi_status)
  # rather than enqueued job rows.

  alias Kiroku.{Doi, Repository, Settings}
  alias Kiroku.Workers.DoiMintWorker

  # ── Fixtures ───────────────────────────────────────────────────────────────

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

  defp create_item(attrs \\ %{}) do
    {:ok, item} =
      Repository.create_item(
        Map.merge(
          %{
            "title" => "Test Thesis",
            "collection_id" => create_collection().id,
            "handle" => "test-item-#{System.unique_integer([:positive])}"
          },
          attrs
        )
      )

    item
  end

  defp enable_doi(provider \\ "mock") do
    Settings.put("doi_enabled", "true")
    Settings.put("doi_provider", provider)
    Settings.put("doi_prefix", "10.5555")
  end

  # ── Adapter dispatch ──────────────────────────────────────────────────────

  describe "adapter/0" do
    test "resolves mock provider by default" do
      assert Doi.adapter() == Kiroku.Doi.Providers.Mock
    end

    test "resolves datacite provider when configured" do
      Settings.put("doi_provider", "datacite")
      assert Doi.adapter() == Kiroku.Doi.Providers.DataCite
    end

    test "falls back to mock on unknown provider key" do
      Settings.put("doi_provider", "crossref")
      assert Doi.adapter() == Kiroku.Doi.Providers.Mock
    end
  end

  describe "mint/1 dispatch" do
    test "returns :disabled when feature is off" do
      item = create_item()
      assert {:error, :disabled} = Doi.mint(item)
    end

    test "returns :already_has_doi when item already has a DOI" do
      enable_doi()
      item = create_item(%{"doi" => "10.9999/existing"})
      assert {:error, :already_has_doi} = Doi.mint(item)
    end

    test "mock provider mints a deterministic DOI from prefix + handle" do
      enable_doi()
      item = create_item()
      assert {:ok, doi} = Doi.mint(item)
      assert doi == "10.5555/#{item.handle}"
    end

    test "mock provider falls back to item id when handle is nil" do
      enable_doi()
      # Bypass Repository.create_item (which always assigns a handle now) to
      # exercise the nil-handle fallback that still applies to legacy/imported
      # rows inserted without going through the context.
      item =
        %Kiroku.Repository.Item{}
        |> Kiroku.Repository.Item.changeset(%{
          "title" => "No Handle Item",
          "collection_id" => create_collection().id,
          "handle" => nil
        })
        |> Kiroku.Repo.insert!()

      assert {:ok, doi} = Doi.mint(item)
      assert doi == "10.5555/#{item.id}"
    end
  end

  # ── Worker ──────────────────────────────────────────────────────────────────

  describe "DoiMintWorker" do
    test "mints and persists the DOI when enabled" do
      enable_doi()
      item = create_item()

      assert :ok == perform_worker(item.id)

      reloaded = Repository.get_item!(item.id)
      assert reloaded.doi == "10.5555/#{item.handle}"
      assert reloaded.doi_status == :minted
      assert reloaded.doi_minted_at != nil
    end

    test "marks :not_required when DOI minting is disabled after enqueue" do
      enable_doi()
      item = create_item()
      Settings.put("doi_enabled", "false")

      assert :ok == perform_worker(item.id)

      reloaded = Repository.get_item!(item.id)
      assert reloaded.doi_status == :not_required
      assert reloaded.doi == nil
    end

    test "marks :minted without re-minting when item already carries a DOI" do
      enable_doi()
      item = create_item(%{"doi" => "10.9999/imported"})

      assert :ok == perform_worker(item.id)

      reloaded = Repository.get_item!(item.id)
      assert reloaded.doi == "10.9999/imported"
      assert reloaded.doi_status == :minted
    end

    test "marks :failed and returns error when provider errors" do
      enable_doi()
      item = create_item()

      # Use the DataCite provider pointed at a closed port so the HTTP call
      # fails fast. Avoids touching the network and exercises the error path.
      Settings.put("doi_provider", "datacite")
      Settings.put("doi_endpoint", "http://127.0.0.1:1")
      Settings.put("doi_username", "fakeuser")
      Settings.put("doi_password", "fakepass")

      assert {:error, _} = perform_worker(item.id)

      reloaded = Repository.get_item!(item.id)
      assert reloaded.doi_status == :failed
      assert reloaded.doi == nil
    end
  end

  # ── publish_item integration ──────────────────────────────────────────────

  describe "publish_item/1 integration (Oban testing: :inline)" do
    test "mints DOI synchronously when enabled and item has no DOI" do
      enable_doi()
      item = create_item()

      assert {:ok, _} = Repository.publish_item(item)

      reloaded = Repository.get_item!(item.id)
      assert reloaded.doi == "10.5555/#{item.handle}"
      assert reloaded.doi_status == :minted
    end

    test "does not mint when DOI minting is disabled" do
      item = create_item()

      assert {:ok, _} = Repository.publish_item(item)

      reloaded = Repository.get_item!(item.id)
      assert reloaded.doi == nil
      assert reloaded.doi_status == :pending
    end

    test "does not re-mint when item already has a DOI" do
      enable_doi()
      item = create_item(%{"doi" => "10.9999/existing"})

      assert {:ok, _} = Repository.publish_item(item)

      reloaded = Repository.get_item!(item.id)
      assert reloaded.doi == "10.9999/existing"
    end
  end

  defp perform_worker(item_id) do
    DoiMintWorker.perform(%Oban.Job{args: %{"item_id" => item_id}})
  end
end
