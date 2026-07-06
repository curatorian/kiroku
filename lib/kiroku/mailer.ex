defmodule Kiroku.Mailer do
  @moduledoc """
  Swoosh mailer. The adapter and credentials are resolved at runtime from the
  DB-backed `Settings` (see `apply_config_from_settings/0`) so the admin can
  switch providers without a redeploy.

  Swoosh reads the application environment on every `deliver/2`, so updating it
  via `Application.put_env/2` takes effect immediately.
  """
  use Swoosh.Mailer, otp_app: :kiroku

  alias Kiroku.Settings

  @doc """
  Reads the current mailer settings and applies them to the application
  environment. Safe to call repeatedly.

  Only takes effect when the provider is `\"smtp\"`; for `\"local\"` (or
  anything unknown) the compile-time adapter is left untouched, which keeps the
  test/dev adapters (`Swoosh.Adapters.Test` / `Local`) intact.
  """
  def apply_config_from_settings do
    case build_config() do
      nil ->
        :ok

      config ->
        Application.put_env(:kiroku, __MODULE__, config)
        :ok
    end
  end

  defp build_config do
    case Settings.mailer_provider() do
      "smtp" ->
        [
          adapter: Swoosh.Adapters.SMTP,
          relay: Settings.mailer_smtp_host(),
          port: Settings.mailer_smtp_port() || 587,
          username: Settings.mailer_smtp_username(),
          password: Settings.mailer_smtp_password(),
          # Upgrade to TLS when the server advertises STARTTLS, and authenticate
          # when credentials are present.
          tls: :if_available,
          auth: :if_available,
          retries: 2
        ]
        |> drop_nil_values()

      _other ->
        nil
    end
  end

  defp drop_nil_values(keyword) do
    Enum.reject(keyword, fn {_k, v} -> is_nil(v) end)
  end
end
