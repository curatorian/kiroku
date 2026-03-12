defmodule Kiroku.Content.Bitstream.Validations.StorageFields do
  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :storage_type) do
      :url -> require_field(changeset, :storage_url)
      :s3 -> require_fields(changeset, [:storage_path, :storage_bucket])
      :local -> require_field(changeset, :storage_path)
      _ -> :ok
    end
  end

  defp require_field(changeset, field) do
    case Ash.Changeset.get_attribute(changeset, field) do
      nil -> {:error, field: field, message: "is required for this storage type"}
      _ -> :ok
    end
  end

  defp require_fields(changeset, fields) do
    Enum.find_value(fields, :ok, fn f -> require_field(changeset, f) end)
  end
end
