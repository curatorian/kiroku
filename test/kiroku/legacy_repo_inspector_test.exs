defmodule Kiroku.LegacyRepo.InspectorTest do
  use Kiroku.DataCase

  alias Kiroku.LegacyRepo.Inspector

  describe "get_config/0" do
    test "returns configuration map" do
      config = Inspector.get_config()

      assert is_map(config)
      assert Map.has_key?(config, :hostname)
      assert Map.has_key?(config, :database)
      assert Map.has_key?(config, :port)
      assert Map.has_key?(config, :username)
      assert Map.has_key?(config, :pool_size)
      assert Map.has_key?(config, :configured?)
    end
  end

  describe "is_configured?/1" do
    test "returns false when required fields are missing" do
      incomplete_config = [
        hostname: "localhost",
        database: nil,
        username: "user",
        password: "pass"
      ]

      refute Inspector.is_configured?(incomplete_config)
    end

    test "returns true when all required fields are present" do
      complete_config = [
        hostname: "localhost",
        database: "test_db",
        username: "user",
        password: "pass"
      ]

      assert Inspector.is_configured?(complete_config)
    end
  end

  describe "extract_version/1" do
    test "extracts first line from version string" do
      version_string = """
      Microsoft SQL Server 2019 (RTM-CU15-GDR) (KB4583462) - 15.0.4102.2 (X64)
      Copyright (C) 2019 Microsoft Corporation
      """

      result = Inspector.extract_version(version_string)
      assert result == "Microsoft SQL Server 2019 (RTM-CU15-GDR) (KB4583462) - 15.0.4102.2 (X64)"
    end

    test "handles unknown input" do
      assert Inspector.extract_version(:not_a_string) == "Unknown"
    end
  end
end
