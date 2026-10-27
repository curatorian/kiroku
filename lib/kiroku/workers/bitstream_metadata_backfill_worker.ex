defmodule Kiroku.Workers.BitstreamMetadataBackfillWorker do
  @moduledoc """
  One-off Oban job filling in NULL `mime_type` / `file_size` on bitstreams
  produced by the legacy imports (see `Kiroku.BitstreamMetadata`).

  Processes a `limit` batch per run and re-enqueues itself while rows remain,
  so it is resumable and never leaves NULLs behind. Run manually:

      %{"limit" => 500} |> Kiroku.Workers.BitstreamMetadataBackfillWorker.new() |> Oban.insert()
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  import Ecto.Query

  require Logger

  alias Kiroku.{BitstreamMetadata, Content, Content.Bitstream, Repo}

  @default_limit 500

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    limit = args["limit"] || @default_limit

    rows =
      Repo.all(
        from bitstream in Bitstream,
          where: is_nil(bitstream.mime_type) or is_nil(bitstream.file_size),
          order_by: [asc: bitstream.id],
          limit: ^limit
      )

    updated = Enum.count(rows, &backfill_row/1)

    if length(rows) == limit do
      Logger.info("[BitstreamMetadataBackfill] updated #{updated}, re-enqueueing continuation")

      %{"limit" => limit}
      |> __MODULE__.new()
      |> Oban.insert()

      :ok
    else
      Logger.info("[BitstreamMetadataBackfill] done — updated #{updated} rows")
      :ok
    end
  end

  defp backfill_row(bitstream) do
    mime = bitstream.mime_type || BitstreamMetadata.derive_mime(bitstream.filename)
    size = bitstream.file_size || BitstreamMetadata.derive_size(bitstream)

    bitstream
    |> Content.update_bitstream(%{mime_type: mime, file_size: size})
    |> case do
      {:ok, _} ->
        true

      {:error, changeset} ->
        Logger.warning(
          "[BitstreamMetadataBackfill] update failed bitstream=#{bitstream.id}: #{inspect(changeset.errors)}"
        )

        false
    end
  end
end
