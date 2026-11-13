defmodule KirokuWeb.AdminAuthorizationTest do
  use KirokuWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Kiroku.{Accounts, Repository, Repo}
  alias Kiroku.Accounts.User

  # ── Fixtures ───────────────────────────────────────────────────────────────

  defp create_user(type) do
    {:ok, user} =
      Accounts.admin_create_user(%{
        "email" => "auth-#{System.unique_integer([:positive])}@example.com",
        "password" => "valid_password_123",
        "user_type" => to_string(type)
      })

    user
  end

  defp confirmed(%User{} = user) do
    Repo.update!(User.confirm_changeset(user))
  end

  defp log_in(conn, user) do
    session_token = Accounts.generate_user_session_token(user)

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session("_kiroku_web_user_token", session_token)
  end

  defp create_item do
    handle = "auth-#{System.unique_integer([:positive])}"

    {:ok, community} =
      Repository.create_community(%{"name" => "C", "handle" => handle})

    {:ok, collection} =
      Repository.create_collection(%{
        "name" => "Coll",
        "community_id" => community.id,
        "handle" => "coll-#{System.unique_integer([:positive])}"
      })

    {:ok, item} =
      Repository.create_item(%{
        "title" => "Review me",
        "collection_id" => collection.id,
        "status" => "submitted"
      })

    item
  end

  # ── Route-level (pipeline) authorization ───────────────────────────────────

  test "anonymous users are sent to log in", %{conn: conn} do
    conn = get(conn, ~p"/admin/users")
    assert redirected_to(conn) == ~p"/users/log_in"
  end

  test "authenticated submitters are denied admin pages", %{conn: conn} do
    conn =
      create_user(:submitter)
      |> then(&log_in(conn, &1))
      |> get(~p"/admin/users")

    assert redirected_to(conn) == ~p"/"
  end

  test "internal users are not staff", %{conn: conn} do
    conn =
      create_user(:internal)
      |> then(&log_in(conn, &1))
      |> get(~p"/admin/settings")

    assert redirected_to(conn) == ~p"/"
  end

  # ── LiveView mount authorization ───────────────────────────────────────────

  test "reviewers can open the review page but not the user list", %{conn: conn} do
    reviewer = create_user(:reviewer)
    item = create_item()
    conn = log_in(conn, reviewer)

    assert redirected_to(get(conn, ~p"/admin/users")) == ~p"/"

    {:ok, view, _html} = live(conn, ~p"/admin/items/#{item.id}/review")
    assert has_element?(view, "#review-form")
  end

  test "submitters cannot open the review page", %{conn: conn} do
    item = create_item()

    assert {:error, {:redirect, %{to: "/"}}} =
             create_user(:submitter)
             |> then(&log_in(conn, &1))
             |> live(~p"/admin/items/#{item.id}/review")
  end

  test "superadmin can access the admin dashboard", %{conn: conn} do
    assert {:ok, _view, _html} =
             create_user(:superadmin) |> then(&log_in(conn, &1)) |> live(~p"/admin")
  end

  # ── Privilege escalation via create_user ───────────────────────────────────

  test "admin-created user_type is clamped when an admin crafts a superadmin payload", %{
    conn: conn
  } do
    admin = create_user(:admin)
    {:ok, view, _html} = log_in(conn, admin) |> live(~p"/admin/users/new")

    email = "rogue-#{System.unique_integer([:positive])}@example.com"

    render_submit(view, "create_user", %{
      "user" => %{
        "email" => email,
        "password" => "valid_password_123",
        "display_name" => "Rogue Admin",
        "user_type" => "superadmin"
      }
    })

    assert user = Accounts.get_user_by_email(email)
    assert user.user_type == :submitter
  end

  test "superadmin can create an admin account", %{conn: conn} do
    superadmin = create_user(:superadmin)
    {:ok, view, _html} = log_in(conn, superadmin) |> live(~p"/admin/users/new")

    email = "new-admin-#{System.unique_integer([:positive])}@example.com"

    render_submit(view, "create_user", %{
      "user" => %{
        "email" => email,
        "password" => "valid_password_123",
        "display_name" => "New Admin",
        "user_type" => "admin"
      }
    })

    assert user = Accounts.get_user_by_email(email)
    assert user.user_type == :admin
  end

  test "submitters cannot even mount the user list to craft create_user events", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} =
             create_user(:submitter) |> then(&log_in(conn, &1)) |> live(~p"/admin/users")
  end

  # ── Email confirmation gate for content creation ───────────────────────────

  test "unconfirmed submitter is blocked from /submit", %{conn: conn} do
    submitter = create_user(:submitter)

    assert {:error, {:live_redirect, %{to: to}}} = log_in(conn, submitter) |> live(~p"/submit")
    assert to == ~p"/my/items"
  end

  test "confirmed submitter passes the confirmation gate on /submit", %{conn: conn} do
    submitter = confirmed(create_user(:submitter))

    # Submission is disabled in the test settings, so the gate passes but the
    # page still redirects — with the *disabled* message, not the confirmation
    # one.
    assert {:error, {:live_redirect, %{to: to, flash: flash}}} =
             log_in(conn, submitter) |> live(~p"/submit")

    assert to == ~p"/my/items"
    assert flash["error"] =~ "currently disabled"
    refute flash["error"] =~ "confirm your email"
  end

  test "can_add_content? rules", _context do
    now = NaiveDateTime.utc_now()

    refute Accounts.can_add_content?(%User{confirmed_at: nil, user_type: :submitter})
    assert Accounts.can_add_content?(%User{confirmed_at: now, user_type: :submitter})
    assert Accounts.can_add_content?(%User{confirmed_at: nil, user_type: :internal})
    assert Accounts.can_add_content?(%User{confirmed_at: nil, user_type: :reviewer})
    assert Accounts.can_add_content?(%User{confirmed_at: nil, user_type: :admin})
    assert Accounts.can_add_content?(%User{confirmed_at: nil, user_type: :superadmin})
  end
end
