defmodule Kiroku.Workers.SafExportWorker do
  @moduledoc """
  Exports items/collections into a DSpace Simple Archive Format zip.

  Enqueued by the `/admin/sync` dashboard. Args:

    * `"target"`        — `"item"` or `"collection"`
    * `"id"`            — handle or UUID of the item/collection
    * `"only"`          — for collections: `"published"` (default) or `"all"`
    * `"triggered_by"`  — user id of the admin who triggered the run

  Writes the zip to `Kiroku.Saf.export_path(job_id)` so the dashboard can offer
  a download link keyed by the Oban job id.
  """

  use Oban.Worker, queue: :sync, max_attempts: 1

  require Logger

  alias Kiroku.{Repo, Saf, Saf.Exporter}
  alias Kiroku.Repository.{Collection, Item}

  @impl Oban.Worker
  def perform(%Oban.Job{id: job_id, args: args}) do
    target = args["target"]
    id = args["id"]
    only = args["only"] || "published"

    tmp = Path.join(System.tmp_dir!(), "kiroku_saf_export_#{job_id}")
    File.rm_rf!(tmp)
    File.mkdir_p!(tmp)

    try do
      result =
        case target do
          "item" -> export_item(id, tmp)
          "collection" -> export_collection(id, tmp, only)
          other -> {:error, "unknown target: #{inspect(other)}"}
        end

      with {:ok, count} <- result,
           zip_path = Saf.export_path(job_id),
           :ok <- File.mkdir_p(Saf.exports_dir()),
           {:ok, ^zip_path} <- Exporter.to_zip(tmp, zip_path) do
        Logger.info("[SafExportWorker] job #{job_id}: exported #{count} item(s) → #{zip_path}")
        :ok
      else
        {:error, reason} = err ->
          Logger.error("[SafExportWorker] job #{job_id} failed: #{inspect(reason)}")
          err
      end
    after
      File.rm_rf!(tmp)
    end
  end

  defp export_item(id, tmp) do
    with {:ok, item} <- fetch_item(id) do
      case Exporter.export_item(item, tmp) do
        {:ok, _dir} -> {:ok, 1}
        {:error, _} = err -> err
      end
    end
  end

  defp export_collection(id, tmp, only) do
    with {:ok, collection} <- fetch_collection(id) do
      filter = if only == "all", do: :all, else: :published

      case Exporter.export_collection(collection.id, tmp, only: filter) do
        {:ok, count, ^tmp} -> {:ok, count}
      end
    end
  end

  defp fetch_item(id) do
    cond do
      String.match?(id, ~r/^[0-9a-f-]{36}$/i) ->
        {:ok, Kiroku.Repository.get_item_with_preloads!(id)}

      true ->
        case Repo.get_by(Item, handle: id) do
          nil -> {:error, "item not found: #{id}"}
          item -> {:ok, Kiroku.Repository.get_item_with_preloads!(item.id)}
        end
    end
  rescue
    _ -> {:error, "item not found: #{id}"}
  end

  defp fetch_collection(id) do
    cond do
      String.match?(id, ~r/^[0-9a-f-]{36}$/i) ->
        {:ok, Repo.get!(Collection, id)}

      true ->
        case Repo.get_by(Collection, handle: id) do
          nil -> {:error, "collection not found: #{id}"}
          c -> {:ok, c}
        end
    end
  rescue
    _ -> {:error, "collection not found: #{id}"}
  end
end
