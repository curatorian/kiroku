defmodule Kiroku.SettingsTest do
  use Kiroku.DataCase, async: true

  alias Kiroku.Settings

  describe "allow_user_submit?/0" do
    test "defaults to false when unset" do
      refute Settings.allow_user_submit?()
    end

    test "returns true when enabled" do
      Settings.put("allow_user_submit", "true")
      assert Settings.allow_user_submit?()
    end

    test "returns false when explicitly disabled" do
      Settings.put("allow_user_submit", "true")
      Settings.put("allow_user_submit", "false")
      refute Settings.allow_user_submit?()
    end
  end

  describe "brand_logo_url/0" do
    test "returns nil when unset (so favicon/wordmark fallbacks apply)" do
      refute Settings.brand_logo_url()
    end

    test "returns the URL when set" do
      Settings.put("brand_logo_url", "/uploads/brand/logo.png")
      assert Settings.brand_logo_url() == "/uploads/brand/logo.png"
    end

    test "normalizes an empty string to nil" do
      Settings.put("brand_logo_url", "/uploads/brand/logo.png")
      Settings.put("brand_logo_url", "")

      refute Settings.brand_logo_url()
    end

    test "normalizes a whitespace-only string to nil" do
      Settings.put("brand_logo_url", "   ")

      refute Settings.brand_logo_url()
    end
  end

  describe "oai_repo_identifier/0" do
    test "defaults to oai:kiroku.ac.id when unset" do
      assert Settings.oai_repo_identifier() == "oai:kiroku.ac.id"
    end

    test "returns the DB value when set" do
      Settings.put("oai_repo_identifier", "oai:repository.unpad.ac.id")

      assert Settings.oai_repo_identifier() == "oai:repository.unpad.ac.id"
    end
  end

  describe "oai_repo_name/0" do
    test "defaults to Kiroku Institutional Repository when unset" do
      assert Settings.oai_repo_name() == "Kiroku Institutional Repository"
    end

    test "returns the DB value when set" do
      Settings.put("oai_repo_name", "Universitas Padjadjaran Repository")

      assert Settings.oai_repo_name() == "Universitas Padjadjaran Repository"
    end
  end

  describe "oai_admin_email/0" do
    test "defaults to admin@kiroku.ac.id when unset" do
      assert Settings.oai_admin_email() == "admin@kiroku.ac.id"
    end

    test "returns the DB value when set" do
      Settings.put("oai_admin_email", "repository@unpad.ac.id")

      assert Settings.oai_admin_email() == "repository@unpad.ac.id"
    end
  end
end
