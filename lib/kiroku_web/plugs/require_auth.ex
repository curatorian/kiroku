defmodule KirokuWeb.Plugs.RequireAuth do
  @moduledoc """
  Plug that requires an authenticated user.
  Redirects to sign-in page if no current_user is present.
  """

  import Plug.Conn
  import Phoenix.Controller

  use KirokuWeb, :verified_routes

  def init(opts), do: opts

  def call(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      return_to = "/" <> Enum.join(conn.path_info, "/")

      conn
      |> put_session(:return_to, return_to)
      |> put_flash(:error, "You must sign in to access this page.")
      |> redirect(to: ~p"/sign-in")
      |> halt()
    end
  end
end
