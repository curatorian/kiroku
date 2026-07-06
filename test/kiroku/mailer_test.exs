defmodule Kiroku.MailerTest do
  # Mutates global Application env, so cannot run alongside mail-sending tests.
  use Kiroku.DataCase, async: false

  alias Kiroku.{Mailer, Settings}

  setup do
    original = Application.get_env(:kiroku, Kiroku.Mailer)

    on_exit(fn ->
      Application.put_env(:kiroku, Kiroku.Mailer, original)
    end)

    :ok
  end

  describe "apply_config_from_settings/0" do
    test "configures the Swoosh SMTP adapter when provider is smtp" do
      Settings.put("mailer_provider", "smtp")
      Settings.put("smtp_host", "smtp.example.com")
      Settings.put("smtp_port", "587")
      Settings.put("smtp_username", "postmaster")
      Settings.put("smtp_password", "secret")

      assert :ok = Mailer.apply_config_from_settings()

      config = Application.get_env(:kiroku, Kiroku.Mailer)
      assert config[:adapter] == Swoosh.Adapters.SMTP
      assert config[:relay] == "smtp.example.com"
      assert config[:port] == 587
      assert config[:username] == "postmaster"
      assert config[:password] == "secret"
    end

    test "leaves the compile-time adapter untouched for local provider" do
      Settings.put("mailer_provider", "local")
      original = Application.get_env(:kiroku, Kiroku.Mailer)

      assert :ok = Mailer.apply_config_from_settings()
      assert Application.get_env(:kiroku, Kiroku.Mailer) == original
    end
  end
end
