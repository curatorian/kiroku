defmodule KirokuWeb.UserSessionController do
  use KirokuWeb, :controller

  alias Kiroku.Accounts
  alias KirokuWeb.UserAuth

  def create(conn, %{"user" => user_params}) do
    %{"email" => email, "password" => password} = user_params

    if user = Accounts.get_user_by_email_and_password(email, password) do
      conn
      |> put_flash(:info, "Selamat datang kembali!")
      |> UserAuth.log_in_user(user, user_params)
    else
      conn
      |> put_flash(:error, "Email atau kata sandi tidak valid.")
      |> redirect(to: ~p"/users/log_in")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Anda telah keluar.")
    |> UserAuth.log_out_user()
  end
end
