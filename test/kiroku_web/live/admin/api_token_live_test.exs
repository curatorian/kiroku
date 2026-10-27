defmodule KirokuWeb.Admin.ApiTokenLiveTest do
  use KirokuWeb.ConnCase, async: true

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Kiroku.{Accounts, Repo}

  defp create_superadmin do
    {:ok, user} =
      Accounts.admin_create_user(%{
        "email" => "owner-#{System.unique_integer([:positive])}@example.com",
        "password" => "valid_password_123",
        "user_type" => "superadmin"
      })

    user
  end

  defp log_in(conn, user) do
    session_token = Accounts.generate_user_session_token(user)

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session("_kiroku_web_user_token", session_token)
  end

  defp submit_token(view, name, token_type) do
    view
    |> element("#token-create-form")
    |> render_submit(%{"token" => %{"name" => name, "token_type" => token_type}})

    # Names include a unique integer so this finds exactly the just-created row.
    Repo.one!(
      from t in Kiroku.ApiToken,
        where: t.name == ^name,
        order_by: [desc: t.inserted_at],
        limit: 1
    )
  end

  # Regression for options_for_select tuple order: the browser must submit
  # value="user"/value="device" (the save handler matches those exactly),
  # never the option label text.
  test "token type select submits real values, not labels", %{conn: conn} do
    user = create_superadmin()
    {:ok, view, _html} = log_in(conn, user) |> live(~p"/admin/api-tokens")

    html = render(view)
    assert html =~ ~s(value="user")
    assert html =~ ~s(value="device")
    refute html =~ ~s(value="Device token (kiosk")

    token = submit_token(view, "Kiosk 01", "device")
    assert Repo.reload!(token).token_type == :device
  end

  test "device token approve action flips approved_at and the row label", %{conn: conn} do
    user = create_superadmin()
    {:ok, view, _html} = log_in(conn, user) |> live(~p"/admin/api-tokens")

    token = submit_token(view, "Kiosk 02", "device")
    assert render(view) =~ "Needs approval"

    view
    |> element(~s(button[phx-click="approve"][phx-value-id="#{token.id}"]))
    |> render_click()

    assert Repo.reload!(token).approved_at
    html = render(view)
    assert html =~ "Approved"
    refute html =~ "Needs approval"
  end

  test "user tokens never show an approve control", %{conn: conn} do
    user = create_superadmin()
    {:ok, view, _html} = log_in(conn, user) |> live(~p"/admin/api-tokens")

    submit_token(view, "User 01", "user")

    html = render(view)
    assert html =~ "User 01"
    refute html =~ "Needs approval"
  end
end
