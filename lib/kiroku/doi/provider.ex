defmodule Kiroku.Doi.Provider do
  @moduledoc """
  Behaviour implemented by DOI-minting providers (DataCite, Crossref, …).

  Each provider receives a `Kiroku.Repository.Item` and returns either the
  minted DOI suffix (the `10.x/YYY` string) or an error. Providers are
  dispatched by `Kiroku.Doi` based on the runtime `doi_provider` setting.
  """

  alias Kiroku.Repository.Item

  @doc "Stable identifier used in logs and admin UI."
  @callback name() :: atom()

  @doc """
  Mint a DOI for `item`. On success returns `{:ok, doi}` where `doi` is the
  full DOI string (e.g. `"10.5555/kiroku-abc123"`). On failure returns
  `{:error, reason}` — Oban will retry the worker.
  """
  @callback mint(item :: Item.t(), opts :: keyword()) ::
              {:ok, doi :: String.t()} | {:error, reason :: term()}
end
