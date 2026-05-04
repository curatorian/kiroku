defmodule Kiroku.Embargo.LifterWorker do
  use Oban.Worker, queue: :embargo, max_attempts: 3

  alias Kiroku.Repo
  alias Kiroku.Repository
  alias Kiroku.Repository.Item
  import Ecto.Query

  @moduledoc """
  Oban worker that runs daily (scheduled via Oban.Cron plugin or a cron task)
  to lift embargoes on items whose embargo_open_date has passed.
  """

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    today = Date.utc_today()

    items_to_lift =
      Repo.all(
        from i in Item,
          where:
            i.status == :embargoed and
              not is_nil(i.embargo_open_date) and
              i.embargo_open_date <= ^today
      )

    results =
      Enum.map(items_to_lift, fn item ->
        case Repository.lift_embargo(item) do
          {:ok, updated} -> {:ok, updated.id}
          {:error, cs} -> {:error, item.id, cs}
        end
      end)

    errors = Enum.filter(results, &match?({:error, _, _}, &1))

    if errors == [] do
      :ok
    else
      {:error, "Failed to lift embargo for items: #{inspect(Enum.map(errors, &elem(&1, 1)))}"}
    end
  end
end
