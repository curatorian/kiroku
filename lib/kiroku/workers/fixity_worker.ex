defmodule Kiroku.Workers.FixityWorker do
  @moduledoc """
  Periodic fixity (checksum) verification for stored bitstreams.

  Scheduled daily via Oban Cron — recomputes MD5s for a batch of bitstreams
  that are due for (re)checking and records the results. Can also be enqueued
  for a single bitstream (`FixityWorker.new(%{"bitstream_id" => id})`).
  """
  use Oban.Worker, queue: :default, max_attempts: 1

  alias Kiroku.Content

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"bitstream_id" => id}}) when is_binary(id) do
    case Content.check_bitstream(id) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def perform(%Oban.Job{}) do
    summary = Content.run_fixity_batch()

    if summary.failed > 0 or summary.errored > 0 do
      require Logger
      Logger.warning("Fixity batch found problems: #{inspect(summary)}")
    end

    :ok
  end
end
