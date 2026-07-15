defmodule KirokuWeb.Admin.SettingsLiveTest do
  use KirokuWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Kiroku.{Accounts, Settings}

  defp create_admin_user do
    {:ok, user} =
      Accounts.admin_create_user(%{
        "email" => "admin-#{System.unique_integer([:positive])}@example.com",
        "password" => "valid_password_123",
        "user_type" => "admin"
      })

    user
  end

  defp log_in(conn, user) do
    token = Accounts.generate_user_session_token(user)

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session("_kiroku_web_user_token", token)
  end

  describe "logo upload" do
    test "renders the logo upload form and no preview when unset", %{conn: conn} do
      conn = log_in(conn, create_admin_user())

      {:ok, view, _html} = live(conn, ~p"/admin/settings")

      assert has_element?(view, "#logo-form")
      # No logo set yet → no preview image.
      refute has_element?(view, "#logo-upload img")
    end

    test "stages a picked file, then stores it as the brand logo on submit", %{conn: conn} do
      conn = log_in(conn, create_admin_user())

      {:ok, view, _html} = live(conn, ~p"/admin/settings")

      refute Settings.brand_logo_url()

      # Pick a PNG — the entry is staged and the Upload button appears.
      logo =
        file_input(view, "#logo-form", :logo, [
          %{name: "logo.png", content: "PNGDATA", size: byte_size("PNGDATA")}
        ])

      assert render_upload(logo, "logo.png") =~ "logo.png"
      assert has_element?(view, "#logo-form button[type='submit']")

      # Submit the form → consume + store the logo.
      _html = view |> element("#logo-form") |> render_submit()

      assert Settings.brand_logo_url() =~ "brand/logo.png"
      # Preview now renders.
      assert has_element?(view, "#logo-upload img")
    end

    test "remove_logo clears the stored logo", %{conn: conn} do
      Settings.put("brand_logo_url", "/uploads/brand/logo.png")
      conn = log_in(conn, create_admin_user())

      {:ok, view, _html} = live(conn, ~p"/admin/settings")

      assert Settings.brand_logo_url() =~ "brand/logo.png"
      assert has_element?(view, "#logo-upload img")

      view |> element("button[phx-click='remove_logo']") |> render_click()

      refute Settings.brand_logo_url()
      refute has_element?(view, "#logo-upload img")
    end
  end
end
