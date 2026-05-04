defmodule KirokuWeb.UserSessionController do
  use KirokuWeb, :controller

  alias KirokuWeb.UserAuth

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Anda telah keluar.")
    |> UserAuth.log_out_user()
  end
end
