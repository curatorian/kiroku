defmodule Mix.Tasks.Kiroku.Saf.Export do
  use Mix.Task

  @shortdoc "Export items/collections to DSpace Simple Archive Format"

  @moduledoc """
  Exports Kiroku items into the DSpace Simple Archive Format.

  ## Usage

      mix kiroku.saf.export --type=ITEM --id=123456789/42 --dest=./export
      mix kiroku.saf.export --type=COLLECTION --id=123456789/7 --dest=./export --zip=./col7.zip
      mix kiroku.saf.export --type=ITEM --id=<uuid> --dest=./export

  ## Options

    * `--type`   — `ITEM` or `COLLECTION` (required)
    * `--id`     — item/collection handle (`123456789/42`) or UUID (required)
    * `--dest`   — destination directory for the SAF tree (required)
    * `--zip`    — optional; if given, also produce a zip at this path
    * `--only`   — for COLLECTION: `published` (default) or `all`
    * `-n`       — sequence number to start at (default 0)

  The heavy lifting lives in `Kiroku.Saf.Exporter`. The dashboard triggers the
  same logic via `Kiroku.Workers.SafExportWorker`.
  """

  alias Kiroku.{Repo, Repository}
  alias Kiroku.Repository.{Collection, Item}
  alias Kiroku.Saf.Exporter

  @requirements ["app.start"]

  def run(args) do
    opts = parse_opts(args)
    type = Keyword.get(opts, :type)
    id = Keyword.get(opts, :id)
    dest = Keyword.get(opts, :dest)

    validate_required!(type, id, dest)

    File.mkdir_p!(dest)

    case String.upcase(type) do
      "ITEM" ->
        item = resolve_item!(id)
        {:ok, dir} = Exporter.export_item(item, dest, seq_start: Keyword.get(opts, :number, 0))
        Mix.shell().info("Exported 1 item → #{dir}")

      "COLLECTION" ->
        collection = resolve_collection!(id)

        filter =
          case Keyword.get(opts, :only) do
            "all" -> :all
            _ -> :published
          end

        {:ok, count, ^dest} = Exporter.export_collection(collection.id, dest, only: filter)
        Mix.shell().info("Exported #{count} items → #{dest}")

      other ->
        Mix.raise("Invalid --type #{inspect(other)}. Use ITEM or COLLECTION.")
    end

    case Keyword.get(opts, :zip) do
      nil ->
        :ok

      zip_path ->
        {:ok, ^zip_path} = Exporter.to_zip(dest, zip_path)
        Mix.shell().info("Wrote zip → #{zip_path}")
    end
  end

  defp resolve_item!(id) do
    cond do
      String.match?(id, ~r/^[0-9a-f-]{36}$/i) ->
        Repository.get_item_with_preloads!(id)

      String.contains?(id, "/") ->
        case Repo.get_by(Item, handle: id) do
          nil -> Mix.raise("No item with handle #{id}")
          item -> Repository.get_item_with_preloads!(item.id)
        end

      true ->
        Mix.raise("Invalid item id #{inspect(id)}. Use a handle or UUID.")
    end
  end

  defp resolve_collection!(id) do
    cond do
      String.match?(id, ~r/^[0-9a-f-]{36}$/i) ->
        Repo.get!(Collection, id)

      true ->
        case Repo.get_by(Collection, handle: id) do
          nil -> Mix.raise("No collection with handle #{id}")
          c -> c
        end
    end
  end

  defp validate_required!(type, id, dest) do
    missing =
      Enum.filter([{"--type", type}, {"--id", id}, {"--dest", dest}], fn {_, v} -> is_nil(v) end)

    if missing != [] do
      Mix.raise("Missing required options: #{Enum.map_join(missing, ", ", &elem(&1, 0))}")
    end
  end

  defp parse_opts(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          type: :string,
          id: :string,
          dest: :string,
          zip: :string,
          only: :string,
          number: :integer
        ]
      )

    opts
  end
end
