defmodule KirokuWeb.BitstreamMissingFileTest do
  use KirokuWeb.ConnCase, async: true

  alias Kiroku.{Content, Repository, Repo}
  alias Kiroku.Content.Bitstream

  # A DB row can outlive its file (restored DB, pruned volume, cross-env
  # data) — the controller must answer 404 instead of crashing Bandit.
  test "a local bitstream whose file is missing renders 404", %{conn: conn} do
    {:ok, community} =
      Repository.create_community(%{
        "name" => "C",
        "handle" => "missing-file-#{System.unique_integer([:positive])}"
      })

    {:ok, collection} =
      Repository.create_collection(%{
        "name" => "Coll",
        "community_id" => community.id,
        "handle" => "missing-file-coll-#{System.unique_integer([:positive])}"
      })

    {:ok, item} =
      Repository.create_item(%{
        "title" => "Missing File Item",
        "collection_id" => collection.id,
        "status" => "published",
        "discoverable" => true
      })

    storage_path =
      "items/#{item.id}/ORIGINAL/does-not-exist-#{System.unique_integer([:positive])}.pdf"

    {:ok, bitstream} =
      %Bitstream{}
      |> Bitstream.changeset(%{
        "item_id" => item.id,
        "filename" => "gone.pdf",
        "bundle_name" => "ORIGINAL",
        "mime_type" => "application/pdf",
        "storage_type" => "local",
        "storage_path" => storage_path
      })
      |> Repo.insert()

    conn = get(conn, ~p"/items/#{item.id}/bitstreams/#{bitstream.id}")

    assert response(conn, 404)
  end
end
