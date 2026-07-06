defmodule Kiroku.Mailer.ConfigWorker do
  @moduledoc """
  A supervised process that applies the DB-backed mailer configuration when the
  application boots (after the Repo is started) and whenever settings change.

  Call `refresh/0` after saving mailer settings so the new adapter/credentials
  take effect immediately.
  """

  use GenServer

  @name __MODULE__

  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: @name)

  @doc "Re-applies the mailer config from the database."
  def refresh, do: GenServer.cast(@name, :refresh)

  @impl true
  def init(_) do
    safe_apply()
    {:ok, %{}}
  end

  @impl true
  def handle_cast(:refresh, state) do
    safe_apply()
    {:noreply, state}
  end

  # The DB may not be migrated on the very first boot (before the setup
  # wizard), so swallow any error rather than crashing the supervision tree.
  defp safe_apply do
    Kiroku.Mailer.apply_config_from_settings()
  rescue
    _ -> :ok
  end
end
