defmodule Kiroku.Workers.DoiMintWorker do
  @moduledoc """
  Mints a DOI for a published item via `Kiroku.Doi`.

  Enqueued by `Repository.publish_item/1` when `doi_enabled` is on and the
  item does not yet carry a DOI. Oban retries failed mints up to
  `max_attempts`; on terminal failure the item is left in `doi_status =
  :failed` so it can be retried manually or surfaced in the admin UI.
  """

  use Oban.Worker, queue: :default, max_attempts: 5

  require Logger

  alias Kiroku.{Doi, Repo, Repository}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"item_id" => item_id}}) do
    item = Repository.get_item!(item_id)

    cond do
      not Kiroku.Settings.doi_enabled?() ->
        # Disabled after enqueue — mark and exit cleanly.
        mark_status(item, :not_required)
        :ok

      item.doi not in [nil, ""] ->
        # Already carries a DOI (import / manual) — nothing to mint.
        mark_status(item, :minted)
        :ok

      true ->
        mark_status(item, :minting)

        case Doi.mint(item) do
          {:ok, doi} ->
            {:ok, _} =
              item
              |> Ecto.Changeset.change(%{
                doi: doi,
                doi_status: :minted,
                doi_minted_at: DateTime.utc_now()
              })
              |> Repo.update()

            :ok

          {:error, :disabled} ->
            mark_status(item, :not_required)
            :ok

          {:error, reason} ->
            Logger.warning("DOI mint failed item=#{item.id}: #{inspect(reason)}")
            mark_status(item, :failed)
            {:error, reason}
        end
    end
  end

  defp mark_status(item, status) do
    {:ok, _} =
      item
      |> Ecto.Changeset.change(%{doi_status: status})
      |> Repo.update()

    :ok
  end
end
