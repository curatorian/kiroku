defmodule KirokuWeb.ContentDispositionTest do
  use KirokuWeb.ConnCase, async: true

  alias Kiroku.{Content, Repository}
  alias KirokuWeb.ContentDisposition

  @korean "대학도서관 보고서.pdf"
  @javanese "ꦧꦱꦗꦮ.pdf"

  describe "header/2" do
    test "ASCII names use the simple quoted form" do
      assert ContentDisposition.header("attachment", "thesis-final.pdf") ==
               ~s(attachment; filename="thesis-final.pdf")
    end

    test "quotes and backslashes are neutralized" do
      assert ContentDisposition.header("inline", ~s(evil".pdf)) ==
               ~s(inline; filename="evil'.pdf")

      assert ContentDisposition.header("inline", "dir\\file.pdf") ==
               ~s(inline; filename="dir'file.pdf")
    end

    test "control characters (header injection) are neutralized" do
      header = ContentDisposition.header("attachment", "ok.pdf\r\nX-Evil: 1")

      refute header =~ "\r"
      refute header =~ "\n"
      assert header == ~s(attachment; filename="ok.pdf''X-Evil: 1")
    end

    test "non-Latin names send an ASCII fallback plus RFC 5987 encoding" do
      header = ContentDisposition.header("attachment", @korean)

      # ASCII-only header value (RFC 7230).
      assert header =~ ~r/^[\x20-\x7E]*$/
      # Fallback for old clients: one underscore per non-ASCII character.
      fallback = String.replace(@korean, ~r/[^\x20-\x7E]/u, "_")
      assert header =~ ~s(filename="#{fallback}")
      # RFC 5987 extended parameter carries the real name.
      assert header =~ ~s(filename*=UTF-8'')
      assert header =~ URI.encode(@korean, &URI.char_unreserved?/1)
    end

    test "Javanese aksara percent-encodes to 3-byte UTF-8 sequences" do
      header = ContentDisposition.header("attachment", @javanese)

      assert header =~ ~s(filename*=UTF-8'')
      assert header =~ URI.encode(@javanese, &URI.char_unreserved?/1)
      assert header =~ ~r/^[\x20-\x7E]*$/
    end

    test "emoji (astral plane) percent-encodes to 4-byte UTF-8 sequences" do
      header = ContentDisposition.header("attachment", "report 📚.pdf")

      assert header =~ ~s(filename*=UTF-8'')
      assert header =~ URI.encode("📚", &URI.char_unreserved?/1)
      assert header =~ ~r/^[\x20-\x7E]*$/
    end
  end

  describe "GET /items/:handle/bitstreams/:id" do
    test "serves a Korean filename as an ASCII-only, RFC 5987 header", %{conn: conn} do
      {item, bs} = fixture("대학도서관-논문.pdf")

      conn = get(conn, ~p"/items/#{item.handle}/bitstreams/#{bs.id}")

      assert response(conn, 200) =~ "fake bytes"

      [content_disposition] = get_resp_header(conn, "content-disposition")
      assert content_disposition =~ ~s(attachment)
      assert content_disposition =~ ~s(filename*=UTF-8'')
      assert content_disposition =~ URI.encode("대학도서관-논문.pdf", &URI.char_unreserved?/1)
      assert content_disposition =~ ~r/^[\x20-\x7E]*$/
    end

    test "serves an ASCII filename unchanged", %{conn: conn} do
      {item, bs} = fixture("thesis.pdf")

      conn = get(conn, ~p"/items/#{item.handle}/bitstreams/#{bs.id}")

      assert response(conn, 200)

      assert get_resp_header(conn, "content-disposition") ==
               [~s(attachment; filename="thesis.pdf")]
    end
  end

  # ── Fixtures ───────────────────────────────────────────────────────────────

  defp fixture(filename) do
    handle = "comm-#{System.unique_integer([:positive])}"

    {:ok, community} =
      Repository.create_community(%{"name" => "Community", "handle" => handle})

    {:ok, collection} =
      Repository.create_collection(%{
        "name" => "Collection",
        "community_id" => community.id,
        "handle" => "coll-#{System.unique_integer([:positive])}"
      })

    {:ok, item} =
      Repository.create_item(%{
        "title" => "Disposition Item",
        "handle" => "disp-#{System.unique_integer([:positive])}",
        "collection_id" => collection.id,
        "status" => "published",
        "discoverable" => true,
        "access_level" => "open"
      })

    path = "disposition-test/#{Ecto.UUID.generate()}.pdf"
    full = Path.join("priv/uploads", path)
    File.mkdir_p!(Path.dirname(full))
    File.write!(full, "%PDF-1.4 fake bytes")

    {:ok, bs} =
      Content.create_bitstream(%{
        item_id: item.id,
        filename: filename,
        bundle_name: :ORIGINAL,
        sequence: 1,
        storage_type: :local,
        storage_path: path,
        mime_type: "application/pdf",
        access_level: :open
      })

    {item, bs}
  end
end
