defmodule Kiroku.Workers.BitstreamMetadataBackfillWorkerTest do
  use Kiroku.DataCase, async: true

  import Ecto.Query

  alias Kiroku.Content.Bitstream
  alias Kiroku.Repo
  alias Kiroku.Workers.BitstreamMetadataBackfillWorker

  setup do
    key = "items/backfill-test/#{System.unique_integer([:positive])}/thesis.pdf"
    full_path = Path.join("priv/uploads", key)
    full_path |> Path.dirname() |> File.mkdir_p!()
    content = "PDF-CONTENT-1234567"
    File.write!(full_path, content)

    on_exit(fn -> File.rm_rf(Path.dirname(full_path)) end)

    # Bitstreams need a real item row (FK).
    {:ok, community} =
      Kiroku.Repository.create_community(%{
        "name" => "Backfill",
        "handle" => "backfill-#{System.unique_integer([:positive])}"
      })

    {:ok, collection} =
      Kiroku.Repository.create_collection(%{
        "name" => "Backfill coll",
        "community_id" => community.id,
        "handle" => "backfill-coll-#{System.unique_integer([:positive])}"
      })

    {:ok, item} =
      Kiroku.Repository.create_item(%{
        "title" => "Backfill Test #{System.unique_integer([:positive])}",
        "collection_id" => collection.id
      })

    {:ok, bitstream} =
      %Bitstream{}
      |> Bitstream.changeset(%{
        item_id: item.id,
        filename: "thesis.pdf",
        bundle_name: "ORIGINAL",
        sequence: 1,
        storage_path: key,
        storage_type: "local",
        access_level: "inherit"
      })
      |> Repo.insert()

    %{bitstream: bitstream, content: content}
  end

  test "backfills mime_type from filename and file_size from local bytes", ctx do
    perform(%{"limit" => 100})

    updated = Repo.reload!(ctx.bitstream)
    assert updated.mime_type == "application/pdf"
    assert updated.file_size == byte_size(ctx.content)
  end

  test "a URL bitstream that cannot be probed gets mime + file_size 0", ctx do
    {:ok, url_bitstream} =
      %Bitstream{}
      |> Bitstream.changeset(%{
        item_id: ctx.bitstream.item_id,
        filename: "abstract.pdf",
        bundle_name: "ORIGINAL",
        sequence: 1,
        storage_type: "url",
        storage_url: "https://dead.invalid/abstract.pdf",
        access_level: "open"
      })
      |> Repo.insert()

    perform(%{"limit" => 100})

    updated = Repo.reload!(url_bitstream)
    assert updated.mime_type == "application/pdf"
    assert updated.file_size == 0

    # The backfill is resumable: nothing is left NULL, so re-runs see no rows.
    assert nil_rows_count() == 0
  end

  defp perform(args), do: BitstreamMetadataBackfillWorker.perform(%Oban.Job{args: args})

  defp nil_rows_count do
    Repo.aggregate(
      from(b in Bitstream, where: is_nil(b.mime_type) or is_nil(b.file_size)),
      :count
    )
  end
end
