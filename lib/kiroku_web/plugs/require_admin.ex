defmodule KirokuWeb.Plugs.RequireAdmin do
  @moduledoc """
  Plug that requires the current user to be an admin or superadmin.
  Returns 403 Forbidden if the user doesn't have admin privileges.
  """

  import Plug.Conn
  import Phoenix.Controller

  use KirokuWeb, :verified_routes

  def init(opts), do: opts

  def call(conn, _opts) do
    user = conn.assigns[:current_user]

    if user && user.user_type in [:admin, :superadmin] do
      conn
    else
      conn
      |> put_flash(:error, "You are not authorized to access this page.")
      |> redirect(to: ~p"/")
      |> halt()
    end
  end
end
