defmodule Kiroku.Doi do
  @moduledoc """
  Dispatch context for DOI minting.

  Resolves a `Kiroku.Doi.Provider` implementation from the runtime
  `doi_provider` setting (DB `system_settings` or env `DOI_PROVIDER`) and
  forwards `mint/2` calls. Used by `Kiroku.Workers.DoiMintWorker`.

  Master switch: `doi_enabled` setting (default `false`). When disabled,
  `mint/1` returns `{:error, :disabled}` and `publish_item` will not enqueue
  the worker at all.
  """

  alias Kiroku.Repository.Item
  alias Kiroku.Settings

  @providers %{
    "mock" => Kiroku.Doi.Providers.Mock,
    "datacite" => Kiroku.Doi.Providers.DataCite
  }

  @doc "Resolves the active provider module from settings."
  def adapter do
    key = Settings.doi_provider()
    Map.get(@providers, key, Kiroku.Doi.Providers.Mock)
  end

  @doc "List of supported provider keys (for the admin UI)."
  def providers, do: Map.keys(@providers)

  @doc """
  Mints a DOI for `item` via the configured provider.

  Returns:
    * `{:ok, doi}`         — full DOI string (e.g. `10.5555/handle-123`)
    * `{:error, :disabled}` — DOI minting is disabled in settings
    * `{:error, reason}`    — provider failure; Oban will retry
  """
  def mint(%Item{} = item, opts \\ []) do
    cond do
      not Settings.doi_enabled?() ->
        {:error, :disabled}

      not is_nil(item.doi) and item.doi != "" ->
        {:error, :already_has_doi}

      true ->
        adapter().mint(item, opts)
    end
  end
end
