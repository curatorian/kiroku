defmodule KirokuWeb.BitstreamReaderRelayTest do
  use KirokuWeb.ConnCase, async: true

  alias Kiroku.{Content, Repository, Repo}
  alias Kiroku.Content.Bitstream

  setup do
    {:ok, community} =
      Repository.create_community(%{
        "name" => "C",
        "handle" => "relay-#{System.unique_integer([:positive])}"
      })

    {:ok, collection} =
      Repository.create_collection(%{
        "name" => "Coll",
        "community_id" => community.id,
        "handle" => "relay-coll-#{System.unique_integer([:positive])}"
      })

    {:ok, item} =
      Repository.create_item(%{
        "title" => "Reader Relay Item",
        "collection_id" => collection.id,
        "status" => "published",
        "discoverable" => true
      })

    %{item: item}
  end

  defp insert_bitstream(item_id, attrs) do
    %Bitstream{}
    |> Bitstream.changeset(
      Map.merge(
        %{
          "item_id" => item_id,
          "filename" => "doc.pdf",
          "bundle_name" => "ORIGINAL",
          "storage_type" => "local"
        },
        attrs
      )
    )
    |> Repo.insert!()
  end

  test "reader=1 relays local bytes inline even with a nil mime", %{conn: conn, item: item} do
    storage_path = "items/#{item.id}/ORIGINAL/#{System.unique_integer([:positive])}.pdf"
    full_path = Path.join("priv/uploads", storage_path)
    File.mkdir_p!(Path.dirname(full_path))
    File.write!(full_path, "%PDF-1.4 relay-test")

    on_exit(fn -> File.rm(full_path) end)

    # mime_type intentionally nil — the reader must derive it from the filename.
    bitstream =
      insert_bitstream(item.id, %{
        "storage_path" => storage_path,
        "mime_type" => nil
      })

    conn = get(conn, ~p"/items/#{item.id}/bitstreams/#{bitstream.id}?reader=1")

    assert response(conn, 200) =~ "%PDF-1.4 relay-test"
    assert get_resp_header(conn, "content-type") |> List.first() =~ "application/pdf"
    assert get_resp_header(conn, "content-disposition") |> List.first() =~ "inline"
  end

  test "reader=1 on an unreachable :url bitstream renders 404", %{conn: conn, item: item} do
    bitstream =
      insert_bitstream(item.id, %{
        "storage_type" => "url",
        "storage_url" => "http://127.0.0.1:1/unreachable.pdf"
      })

    conn = get(conn, ~p"/items/#{item.id}/bitstreams/#{bitstream.id}?reader=1")

    assert response(conn, 404)
  end

  test "reader=1 on a non-PDF renders 404", %{conn: conn, item: item} do
    bitstream =
      insert_bitstream(item.id, %{
        "filename" => "figure.png",
        "mime_type" => "image/png",
        "storage_type" => "url",
        "storage_url" => "https://example.com/figure.png"
      })

    conn = get(conn, ~p"/items/#{item.id}/bitstreams/#{bitstream.id}?reader=1")

    assert response(conn, 404)
  end

  test "without reader=1, an :url bitstream keeps redirecting", %{conn: conn, item: item} do
    bitstream =
      insert_bitstream(item.id, %{
        "storage_type" => "url",
        "storage_url" => "https://example.com/legacy.pdf",
        "mime_type" => "application/pdf"
      })

    conn = get(conn, ~p"/items/#{item.id}/bitstreams/#{bitstream.id}")

    assert redirected_to(conn) == "https://example.com/legacy.pdf"
  end

  test "a .pdf filename counts as reader-eligible even with a generic mime", %{
    conn: conn,
    item: item
  } do
    # Reader-eligibility is mirrored in the sidebar button logic (LiveView),
    # exercised here through the relay endpoint's own pdf gate.
    storage_path = "items/#{item.id}/ORIGINAL/#{System.unique_integer([:positive])}.pdf"
    full_path = Path.join("priv/uploads", storage_path)
    File.mkdir_p!(Path.dirname(full_path))
    File.write!(full_path, "%PDF-1.4 generic-mime")

    on_exit(fn -> File.rm(full_path) end)

    bitstream =
      insert_bitstream(item.id, %{
        "storage_path" => storage_path,
        "mime_type" => "application/octet-stream"
      })

    conn = get(conn, ~p"/items/#{item.id}/bitstreams/#{bitstream.id}?reader=1")

    assert response(conn, 200) =~ "%PDF-1.4 generic-mime"
  end
end
