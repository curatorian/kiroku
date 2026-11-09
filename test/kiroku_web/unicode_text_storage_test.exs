defmodule KirokuWeb.UnicodeTextStorageTest do
  use KirokuWeb.ConnCase, async: true

  alias Kiroku.{Accounts, ApiTokens, Repository, Repo}

  @moduledoc """
  Non-Latin text (Arabic, Korean, Japanese, Javanese aksara, Sundanese, emoji)
  must round-trip through every storage and render layer byte-for-byte:
  Postgres via Ecto, the JSON API, and the server-rendered item page.

  Javanese (U+A980–A9BF) and Sundanese (U+1B80–1BBF) cover non-Latin scripts
  beyond the BMP assumptions; emoji cover 4-byte UTF-8 (astral plane).
  """

  @arabic "تحليل وسائل التواصل الاجتماعي في المكتبات الجامعية"
  @korean "대학도서관 미디어 정보 서비스 연구"
  @japanese "大学図書館におけるメディア情報サービスの研究"
  @javanese "ꦧꦱꦗꦮ ꦭꦤ꧀ ꦥꦿꦭꦩ꧀ꦧꦔꦤ꧀"
  @sundanese "ᮞᮥᮔ᮪ᮓ ᮘᮞ ᮕᮢᮔ᮪ᮒ"
  @mixed_rtl "الرياضيات dan Matematika 2024"
  @emoji "Perpustakaan 📚 디지털 아카이브"

  setup do
    handle = "comm-#{System.unique_integer([:positive])}"

    {:ok, community} =
      Repository.create_community(%{"name" => "Community", "handle" => handle})

    {:ok, collection} =
      Repository.create_collection(%{
        "name" => "Collection",
        "community_id" => community.id,
        "handle" => "coll-#{System.unique_integer([:positive])}"
      })

    %{collection: collection}
  end

  test "the database runs with UTF8 encoding", _ctx do
    {:ok, %Postgrex.Result{rows: rows}} = Repo.query("SHOW server_encoding")
    assert rows == [["UTF8"]]
  end

  describe "repository round-trip" do
    test "stores Arabic, Korean, Japanese, Javanese and Sundanese verbatim", %{collection: c} do
      {:ok, item} =
        Repository.create_item(%{
          "title" => @arabic,
          "title_alt" => @korean,
          "abstract" => @japanese,
          "abstract_alt" => @javanese,
          "student_name" => @sundanese,
          "collection_id" => c.id,
          "status" => "published",
          "discoverable" => true,
          "access_level" => "open"
        })

      reloaded = Repository.get_item_with_preloads!(item.handle)

      # Binary equality — byte-for-byte, no NFC normalization, no truncation.
      assert reloaded.title == @arabic
      assert reloaded.title_alt == @korean
      assert reloaded.abstract == @japanese
      assert reloaded.abstract_alt == @javanese
      assert reloaded.student_name == @sundanese
    end

    test "mixed RTL and astral-plane (emoji) text survives an update", %{collection: c} do
      {:ok, item} =
        Repository.create_item(%{
          "title" => "Latin Placeholder",
          "collection_id" => c.id,
          "status" => "published"
        })

      {:ok, updated} =
        Repository.update_item(item, %{
          "title" => @mixed_rtl,
          "abstract" => @emoji,
          "title_alt" => String.duplicate("ꦧ", 500)
        })

      assert updated.title == @mixed_rtl
      assert updated.abstract == @emoji

      # validate_length(:title, max: 500) counts graphemes, not bytes — a
      # 500-grapheme aksara title (1500 bytes) must pass.
      assert String.length(updated.title_alt) == 500

      reloaded = Repository.get_item_with_preloads!(item.handle)
      assert reloaded.title == @mixed_rtl
    end
  end

  describe "JSON API round-trip" do
    test "POST echoes and persists non-Latin titles and abstracts", %{collection: c} do
      user = submitter()
      token_conn = token_conn(user)

      body = %{
        "item" => %{
          "title" => @korean,
          "title_alt" => @javanese,
          "abstract" => @sundanese,
          "collection_id" => c.id
        }
      }

      conn = post(token_conn, ~p"/api/v1/items", body)

      assert %{"data" => data} = json_response(conn, 201)
      assert data["title"] == @korean
      assert data["title_alt"] == @javanese
      assert data["abstract"] == @sundanese

      reloaded = Repository.get_item_with_preloads!(data["id"])
      assert reloaded.title == @korean
      assert reloaded.title_alt == @javanese
      assert reloaded.abstract == @sundanese
    end
  end

  describe "server-rendered page" do
    test "item page renders the non-Latin title verbatim", %{collection: c} do
      {:ok, item} =
        Repository.create_item(%{
          "title" => @japanese,
          "title_alt" => @korean,
          "abstract" => @arabic,
          "collection_id" => c.id,
          "status" => "published",
          "discoverable" => true,
          "access_level" => "open"
        })

      html = response(get(build_conn(), ~p"/items/#{item.handle}"), 200)

      assert html =~ @japanese
      assert html =~ @korean
      assert html =~ @arabic
      # The title is also the document title (SEO).
      assert html =~ " #{@japanese} — Kiroku"
    end
  end

  # ── Helpers ────────────────────────────────────────────────────────────────

  defp submitter do
    {:ok, user} =
      Accounts.register_user(%{
        "email" => "unicode-#{System.unique_integer([:positive])}@example.test",
        "password" => "password123456"
      })

    user
  end

  defp token_conn(%{id: _} = user) do
    {:ok, raw, _} = ApiTokens.create_token(user, "test-token")
    build_conn() |> put_req_header("authorization", "Bearer #{raw}")
  end
end
