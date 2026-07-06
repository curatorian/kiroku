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
end
