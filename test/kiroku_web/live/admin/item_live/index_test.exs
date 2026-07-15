defmodule KirokuWeb.Admin.ItemLive.IndexTest do
  use KirokuWeb.ConnCase, async: true

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Kiroku.{Accounts, Repo, Repository}
  alias Kiroku.Repository.Item

  # ── Fixtures ────────────────────────────────────────────────────────────────

  defp create_admin_user do
    {:ok, user} =
      Accounts.admin_create_user(%{
        "email" => "admin-#{System.unique_integer([:positive])}@example.com",
        "password" => "valid_password_123",
        "user_type" => "admin"
      })

    user
  end

  defp create_collection do
    handle = "comm-#{System.unique_integer([:positive])}"

    {:ok, community} = Repository.create_community(%{"name" => "Community", "handle" => handle})

    {:ok, collection} =
      Repository.create_collection(%{
        "name" => "Collection",
        "community_id" => community.id,
        "handle" => "coll-#{System.unique_integer([:positive])}"
      })

    collection
  end

  # UserAuth.log_in_user/2 ends with a redirect (it's the login action), so for
  # tests we set the session token directly on a test session instead.
  defp log_in(conn, user) do
    token = Accounts.generate_user_session_token(user)

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session("_kiroku_web_user_token", token)
  end

  defp latest_item do
    Repo.one(from i in Item, order_by: [desc: i.inserted_at], limit: 1)
  end

  # ── Rendering ───────────────────────────────────────────────────────────────

  describe "new item form — rendering" do
    test "renders identity, relations, and files sections", %{conn: conn} do
      conn = log_in(conn, create_admin_user())

      {:ok, view, _html} = live(conn, ~p"/admin/items/new")

      assert has_element?(view, "#item-form")
      assert has_element?(view, "#item-type-select")
      assert has_element?(view, "#relations-section")
      assert has_element?(view, "#files-section")
      # Skripsi is the default type, so the per-chapter dropzone is shown.
      assert has_element?(view, "#dropzone-chapters")
    end

    test "requires authentication", %{conn: conn} do
      # Anonymous users are redirected by the ensure_authenticated mount hook.
      assert {:error, {:redirect, _}} = live(conn, ~p"/admin/items/new")
    end

    test "file fields follow the selected jenis karya", %{conn: conn} do
      conn = log_in(conn, create_admin_user())

      {:ok, view, _html} = live(conn, ~p"/admin/items/new")

      render_change(view, "type_changed", %{"item" => %{"item_type" => "karya_kreatif"}})

      # Chapters only apply to thesis types.
      refute has_element?(view, "#dropzone-chapters")
      # Media is relevant for creative works.
      assert has_element?(view, "#dropzone-media")

      render_change(view, "type_changed", %{"item" => %{"item_type" => "skripsi"}})
      assert has_element?(view, "#dropzone-chapters")
    end
  end

  # ── Creation ────────────────────────────────────────────────────────────────

  describe "new item form — creation" do
    setup do
      %{collection: create_collection(), user: create_admin_user()}
    end

    test "succeeds with valid params", %{
      conn: conn,
      collection: collection,
      user: user
    } do
      conn = log_in(conn, user)
      {:ok, view, _html} = live(conn, ~p"/admin/items/new")

      html =
        render_submit(view, :save, %{
          "item" => %{
            "title" => "Skripsi Uji Coba",
            "collection_id" => collection.id,
            "item_type" => "skripsi",
            "status" => "draft",
            "access_level" => "open",
            "language" => "id"
          }
        })

      assert html =~ "Item created successfully."

      item = latest_item()
      assert item.title == "Skripsi Uji Coba"
      assert item.collection_id == collection.id
      assert item.submitter_id == user.id
      # Handles are always generated now — never nil.
      assert item.handle != nil
    end

    test "derives the handle from student_id when provided", %{
      conn: conn,
      collection: collection,
      user: user
    } do
      conn = log_in(conn, user)
      {:ok, view, _html} = live(conn, ~p"/admin/items/new")

      render_submit(view, :save, %{
        "item" => %{
          "title" => "Handle from NPM",
          "collection_id" => collection.id,
          "item_type" => "skripsi",
          "student_id" => "210210160150"
        }
      })

      assert latest_item().handle == "210210160150"
    end

    test "generates a short fallback handle when no student_id", %{
      conn: conn,
      collection: collection,
      user: user
    } do
      conn = log_in(conn, user)
      {:ok, view, _html} = live(conn, ~p"/admin/items/new")

      render_submit(view, :save, %{
        "item" => %{"title" => "No NPM", "collection_id" => collection.id}
      })

      item = latest_item()
      assert item.handle != nil
      assert String.length(item.handle) == 8
    end

    test "persists authors, advisors, and keywords", %{
      conn: conn,
      collection: collection,
      user: user
    } do
      conn = log_in(conn, user)
      {:ok, view, _html} = live(conn, ~p"/admin/items/new")

      render_submit(view, :save, %{
        "item" => %{"title" => "With Relations", "collection_id" => collection.id},
        "authors" => %{
          "a1" => %{"author_name" => "Budi Santoso", "affiliation" => "Unpad"},
          "a2" => %{"author_name" => "  ", "affiliation" => "blank dropped"}
        },
        "advisors" => %{
          "d1" => %{"advisor_name" => "Dr. X", "advisor_role" => "main_advisor"}
        },
        "keywords" => "hukum, pidana\nkomparatif"
      })

      reloaded = Repository.get_item_with_preloads!(latest_item().id)

      assert Enum.map(reloaded.item_authors, & &1.author_name) == ["Budi Santoso"]
      assert hd(reloaded.item_advisors).advisor_name == "Dr. X"
      assert Enum.map(reloaded.item_keywords, & &1.keyword) == ["hukum", "pidana", "komparatif"]
    end

    test "does not persist and re-renders the form when required fields are missing", %{
      conn: conn,
      collection: collection,
      user: user
    } do
      conn = log_in(conn, user)
      {:ok, view, _html} = live(conn, ~p"/admin/items/new")

      _html =
        render_submit(view, :save, %{
          "item" => %{"title" => "", "collection_id" => collection.id}
        })

      # Form stays on the :new page; nothing was persisted.
      assert has_element?(view, "#item-form")
      assert Repo.aggregate(Item, :count) == 0
    end
  end
end
