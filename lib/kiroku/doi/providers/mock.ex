defmodule Kiroku.Doi.Providers.Mock do
  @moduledoc """
  No-op provider for dev and test environments (and production setups without
  a DataCite/Crossref account).

  Mints a deterministic, clearly-fake DOI derived from the item's handle so
  tests can assert on the value without touching the network. The prefix is
  the runtime `doi_prefix` setting, defaulting to `10.5555`.
  """

  @behaviour Kiroku.Doi.Provider

  alias Kiroku.Repository.Item
  alias Kiroku.Settings

  @impl true
  def name, do: :mock

  @impl true
  def mint(%Item{} = item, _opts) do
    prefix = Settings.doi_prefix()
    suffix = item.handle || item.id
    {:ok, "#{prefix}/#{suffix}"}
  end
end
