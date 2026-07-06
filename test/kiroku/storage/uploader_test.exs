defmodule Kiroku.Storage.UploaderTest do
  use Kiroku.DataCase, async: true

  alias Kiroku.Storage.Uploader

  describe "record_attrs/1" do
    test ":local returns a local storage type with no bucket key" do
      assert Uploader.record_attrs(:local) == %{storage_type: :local}
    end

    test ":s3 returns an s3 storage type and includes the bucket field" do
      attrs = Uploader.record_attrs(:s3)

      assert attrs.storage_type == :s3
      # bucket resolves from Kiroku.Settings at call time; presence is what matters
      assert Map.has_key?(attrs, :storage_bucket)
    end

    test "default arity mirrors the live adapter so records always match the destination" do
      assert Uploader.record_attrs() == Uploader.record_attrs(Kiroku.Settings.storage_adapter())
    end

    test "unknown adapter falls back to :local" do
      assert Uploader.record_attrs(:wat) == %{storage_type: :local}
    end
  end
end
