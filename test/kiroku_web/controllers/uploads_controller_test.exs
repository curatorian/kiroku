defmodule KirokuWeb.UploadsControllerTest do
  use KirokuWeb.ConnCase, async: true

  alias Kiroku.{Accounts, Repository}
  alias Kiroku.Content.Bitstream

  # ── Fixtures ───────────────────────────────────────────────────────────────

  setup do
    {:ok, community} =
      Repository.create_community(%{
        "name" => "C",
        "handle" => "uploads-#{System.unique_integer([:positive])}"
      })

    {:ok, collection} =
      Repository.create_collection(%{
        "name" => "Coll",
        "community_id" => community.id,
        "handle" => "uploads-coll-#{System.unique_integer([:positive])}"
      })

    # Published but access-closed: metadata is staff-visible only, files too.
    {:ok, item} =
      Repository.create_item(%{
        "title" => "Upload ACL Item",
        "collection_id" => collection.id,
        "status" => "published",
        "discoverable" => true,
        "access_level" => "closed"
      })

    storage_path = "items/#{item.id}/ORIGINAL/#{System.unique_integer([:positive])}.pdf"
    full_path = Path.join("priv/uploads", storage_path)
    File.mkdir_p!(Path.dirname(full_path))
    File.write!(full_path, "%PDF-1.4 acl-test")

    {:ok, _bitstream} =
      %Bitstream{}
      |> Bitstream.changeset(%{
        "item_id" => item.id,
        "filename" => "thesis.pdf",
        "bundle_name" => "ORIGINAL",
        "mime_type" => "application/pdf",
        "storage_type" => "local",
        "storage_path" => storage_path
      })
      |> Kiroku.Repo.insert()

    on_exit(fn -> File.rm(full_path) end)

    %{item: item, storage_path: storage_path}
  end

  defp log_in(conn, user) do
    session_token = Accounts.generate_user_session_token(user)

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session("_kiroku_web_user_token", session_token)
  end

  # ── Access control ─────────────────────────────────────────────────────────

  test "anonymous users cannot fetch a closed item's file", %{conn: conn, storage_path: path} do
    conn = get(conn, "/uploads/#{path}")
    assert response(conn, 403)
  end

  test "staff can fetch the file", %{conn: conn, storage_path: path} do
    {:ok, user} =
      Accounts.admin_create_user(%{
        "email" => "uploads-admin-#{System.unique_integer([:positive])}@example.com",
        "password" => "valid_password_123",
        "user_type" => "superadmin"
      })

    conn = log_in(conn, user) |> get("/uploads/#{path}")

    assert response(conn, 200) =~ "%PDF-1.4 acl-test"
  end

  test "unknown storage keys 404", %{conn: conn} do
    conn = get(conn, "/uploads/items/00000000-0000-0000-0000-000000000000/ORIGINAL/none.pdf")
    assert response(conn, 404)
  end

  test "path traversal is rejected", %{conn: conn} do
    conn = get(conn, "/uploads/%2e%2e/mix.exs")
    assert response(conn, 404)
  end

  # ── Brand assets stay public ───────────────────────────────────────────────

  test "brand files are served without authentication", %{conn: conn} do
    key = "brand/test-logo-#{System.unique_integer([:positive])}.svg"
    full_path = Path.join("priv/uploads", key)
    File.mkdir_p!(Path.dirname(full_path))
    File.write!(full_path, "<svg>logo</svg>")

    on_exit(fn -> File.rm(full_path) end)

    conn = get(conn, "/uploads/#{key}")

    assert response(conn, 200) =~ "<svg>logo</svg>"
  end
end
