defmodule Kiroku.Accounts.UserNotifier do
  import Swoosh.Email
  alias Kiroku.Mailer

  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from({"Kiroku Repository", "no-reply@kiroku.ac.id"})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  def deliver_confirmation_instructions(user, url) do
    deliver(user.email, "Konfirmasi Akun Kiroku", """
    Halo #{user.display_name || user.email},

    Silakan konfirmasi akun Anda dengan membuka tautan berikut:

    #{url}

    Tautan ini berlaku selama 7 hari.
    Jika Anda tidak mendaftarkan akun ini, abaikan email ini.
    """)
  end

  def deliver_reset_password_instructions(user, url) do
    deliver(user.email, "Reset Kata Sandi — Kiroku Repository", """
    Halo #{user.display_name || user.email},

    Anda telah meminta reset kata sandi. Klik tautan berikut untuk melanjutkan:

    #{url}

    Tautan ini berlaku selama 24 jam.
    Jika Anda tidak meminta reset ini, abaikan email ini.
    """)
  end

  def deliver_update_email_instructions(user, url) do
    deliver(user.email, "Perbarui Email — Kiroku Repository", """
    Halo #{user.display_name || user.email},

    Anda telah meminta perubahan alamat email. Klik tautan berikut untuk mengkonfirmasi:

    #{url}

    Tautan ini berlaku selama 7 hari.
    Jika Anda tidak meminta perubahan ini, abaikan email ini.
    """)
  end
end
