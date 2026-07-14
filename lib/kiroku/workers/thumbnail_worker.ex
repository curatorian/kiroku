defmodule Kiroku.Workers.ThumbnailWorker do
  @moduledoc """
  Generates a first-page thumbnail from an ORIGINAL PDF and stores it as a
  THUMBNAIL bitstream on the same item.

  Enqueued by `Content.create_bitstream/1` for ORIGINAL bitstreams with
  stored bytes. The worker skips gracefully when:

    * the source is not a PDF (non-PDF ORIGINALs)
    * the item already has a THUMBNAIL bitstream (user cover / legacy import)
    * `pdftoppm` (poppler-utils) is not installed

  Matches the `PdfTextWorker` pattern — temp-file based since Elixir 1.20
  dropped `System.cmd/3`'s `:input` option.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  alias Kiroku.Content

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"bitstream_id" => id}}) do
    case Content.generate_thumbnail(id) do
      {:ok, %Content.Bitstream{}} ->
        :ok

      {:ok, reason} when reason in [:skipped, :no_pdftoppm] ->
        # Not retryable — the source is not a PDF, a thumbnail already
        # exists, or poppler-utils is missing. Either way, re-running
        # won't help.
        if reason == :no_pdftoppm do
          Logger.warning("ThumbnailWorker: pdftoppm missing, skipping bitstream=#{id}")
        end

        :ok

      {:error, reason} ->
        Logger.warning("ThumbnailWorker failed bitstream=#{id}: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
