defmodule Kiroku.Workers.PdfTextWorker do
  @moduledoc """
  Extracts text from a single bitstream (PDF) and folds it into the parent
  item's `extracted_text` cache, which the PostgreSQL `search_vector`
  generated column rolls into the GIN-indexed search index.

  Enqueued by `Content.create_bitstream/1` whenever a PDF lands in an
  ORIGINAL or CHAPTER bundle. Safe to retry — extraction is idempotent.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  alias Kiroku.Content

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"bitstream_id" => id}}) do
    case Content.extract_text(id) do
      {:ok, _} ->
        :ok

      # Don't retry these — re-running won't help.
      {:error, :pdftotext_not_found} ->
        Logger.warning("PdfTextWorker: pdftotext missing, skipping bitstream=#{id}")
        :ok

      {:error, :no_storage_path} ->
        Logger.warning("PdfTextWorker: no stored bytes, skipping bitstream=#{id}")
        :ok

      {:error, reason} ->
        Logger.warning("PdfTextWorker failed bitstream=#{id}: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
