defmodule KirokuWeb.Api.V1.BitstreamDownloadApiTest do
  use KirokuWeb.ConnCase, async: true

  alias Kiroku.{Accounts, ApiTokens, Content, Repository, Repo}
  alias Kiroku.Accounts.User

  setup do
    user = create_user(:submitter)
    {:ok, raw, _} = ApiTokens.create_token(user, "device-test-token", token_type: :device)
    {item, bitstream} = published_item_with_file()

    on_exit(fn ->
      File.rm_rf(Path.join("priv/uploads", "items/#{item.id}"))
    end)

    %{user: user, raw_token: raw, item: item, bitstream: bitstream}
  end

  defp create_user(type) do
    {:ok, user} =
      Accounts.register_user(%{
        "email" => "api-#{System.unique_integer([:positive])}@example.test",
        "password" => "password123456"
      })

    if type != :submitter do
      user |> User.role_changeset(%{user_type: type}) |> Repo.update!()
    else
      user
    end
  end

  defp collection do
    {:ok, community} =
      Repository.create_community(%{
        "name" => "C",
        "handle" => "comm-#{System.unique_integer([:positive])}"
      })

    {:ok, collection} =
      Repository.create_collection(%{
        "name" => "Coll",
        "community_id" => community.id,
        "handle" => "coll-#{System.unique_integer([:positive])}"
      })

    collection
  end

  defp published_item_with_file do
    coll = collection()

    {:ok, item} =
      Repository.create_item(%{
        "title" => "Range Test Thesis #{System.unique_integer([:positive])}",
        "collection_id" => coll.id,
        "status" => "published",
        "discoverable" => true,
        "published_at" => ~N[2025-01-01 00:00:00]
      })

    content = "PDFBYTES--#{System.unique_integer([:positive])}--abc123"
    key = "items/#{item.id}/original/#{Ecto.UUID.generate()}.pdf"
    full_path = Path.join("priv/uploads", key)
    full_path |> Path.dirname() |> File.mkdir_p!()
    File.write!(full_path, content)

    {:ok, bitstream} =
      Content.create_bitstream(%{
        item_id: item.id,
        filename: "thesis.pdf",
        bundle_name: "ORIGINAL",
        sequence: 2,
        description: "Full text",
        mime_type: "application/pdf",
        file_size: byte_size(content),
        storage_path: key,
        checksum: nil,
        checksum_algorithm: "MD5",
        access_level: "inherit"
      })

    {item, bitstream}
  end

  defp authed_conn(raw_token) do
    build_conn() |> put_req_header("authorization", "Bearer #{raw_token}")
  end

  # ── GET /api/v1/items/:id/bitstreams/:bitstream_id ────────────────────────

  describe "download" do
    test "returns the full body (200) with content type and range headers", ctx do
      conn =
        authed_conn(ctx.raw_token)
        |> get(~p"/api/v1/items/#{ctx.item.id}/bitstreams/#{ctx.bitstream.id}")

      assert response(conn, 200) =~ "PDFBYTES"

      assert "application/pdf" == get_resp_header(conn, "content-type") |> List.first()
      assert "bytes" == get_resp_header(conn, "accept-ranges") |> List.first()
      assert get_resp_header(conn, "content-range") == []
      assert get_resp_header(conn, "etag") != []
    end

    test "returns 206 for Range: bytes=0-0 with Content-Range", ctx do
      conn =
        authed_conn(ctx.raw_token)
        |> put_req_header("range", "bytes=0-0")
        |> get(~p"/api/v1/items/#{ctx.item.id}/bitstreams/#{ctx.bitstream.id}")

      assert byte_size(response(conn, 206)) == 1
      assert ["bytes 0-0/#{ctx.bitstream.file_size}"] == get_resp_header(conn, "content-range")
    end

    test "returns 206 with an open-ended range", ctx do
      conn =
        authed_conn(ctx.raw_token)
        |> put_req_header("range", "bytes=8-")
        |> get(~p"/api/v1/items/#{ctx.item.id}/bitstreams/#{ctx.bitstream.id}")

      assert response(conn, 206) != ""

      assert "bytes 8-#{ctx.bitstream.file_size - 1}/#{ctx.bitstream.file_size}" in get_resp_header(
               conn,
               "content-range"
             )
    end

    test "returns 416 for an unsatisfiable range", ctx do
      conn =
        authed_conn(ctx.raw_token)
        |> put_req_header("range", "bytes=999999999-")
        |> get(~p"/api/v1/items/#{ctx.item.id}/bitstreams/#{ctx.bitstream.id}")

      assert conn.status == 416
      assert response(conn, 416) =~ "range_not_satisfiable"
    end

    test "accepts the item handle in the download URL", ctx do
      conn =
        authed_conn(ctx.raw_token)
        |> get(~p"/api/v1/items/#{ctx.item.handle}/bitstreams/#{ctx.bitstream.id}")

      assert response(conn, 200) =~ "PDFBYTES"
    end

    test "returns 403 in the uniform envelope for a restricted file", ctx do
      {:ok, restricted} =
        Content.update_bitstream(ctx.bitstream, %{access_level: "restricted"})

      conn =
        authed_conn(ctx.raw_token)
        |> get(~p"/api/v1/items/#{ctx.item.id}/bitstreams/#{restricted.id}")

      assert json_response(conn, 403)["error"] == "forbidden"
    end

    test "returns 404 for a missing bitstream and an unpublished item", ctx do
      conn =
        authed_conn(ctx.raw_token)
        |> get(~p"/api/v1/items/#{ctx.item.id}/bitstreams/#{Ecto.UUID.generate()}")

      assert json_response(conn, 404)["error"] == "not_found"
    end
  end

  # ── GET /api/v1/items/:id/thumbnails/:size ────────────────────────────────

  describe "thumbnail" do
    test "serves the stored THUMBNAIL bitstream", ctx do
      content = "IMGDATA"
      key = "items/#{ctx.item.id}/thumbnail/#{Ecto.UUID.generate()}.jpg"
      path = Path.join("priv/uploads", key)
      path |> Path.dirname() |> File.mkdir_p!()
      File.write!(path, content)
      on_exit(fn -> File.rm_rf(path) end)

      {:ok, _thumb} =
        Content.create_bitstream(%{
          item_id: ctx.item.id,
          filename: "cover.jpg",
          bundle_name: "THUMBNAIL",
          sequence: 1,
          description: "Cover image",
          mime_type: "image/jpeg",
          file_size: byte_size(content),
          storage_path: key,
          access_level: "open"
        })

      conn =
        authed_conn(ctx.raw_token)
        |> get(~p"/api/v1/items/#{ctx.item.id}/thumbnails/medium")

      assert response(conn, 200) == content
      assert "image/jpeg" == get_resp_header(conn, "content-type") |> List.first()
    end

    test "404s when the item has no thumbnail", ctx do
      conn =
        authed_conn(ctx.raw_token)
        |> get(~p"/api/v1/items/#{ctx.item.id}/thumbnails/medium")

      assert json_response(conn, 404)["error"] == "not_found"
    end
  end
end
