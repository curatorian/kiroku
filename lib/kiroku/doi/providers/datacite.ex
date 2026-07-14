defmodule Kiroku.Doi.Providers.DataCite do
  @moduledoc """
  DataCite REST API provider.

  Mints a DOI by POSTing to the DataCite REST API (`/dois`) with a
  DataCite-JSON payload. The DOI suffix is derived from the item's handle so
  the same item always maps to the same DOI on retries.

  Required settings (DB `system_settings` or env):
    * `doi_prefix`     — e.g. `10.5555`
    * `doi_username`   — DataCite username (e.g. `KIT.KIROKU`)
    * `doi_password`   — DataCite password

  Optional:
    * `doi_endpoint`   — defaults to `https://api.datacite.org`
    * `doi_publisher`  — defaults to the brand name

  See https://support.datacite.org/docs/api for the full field reference.
  """

  @behaviour Kiroku.Doi.Provider

  require Logger

  alias Kiroku.Repository.Item
  alias Kiroku.Settings

  @default_endpoint "https://api.datacite.org"

  @impl true
  def name, do: :datacite

  @impl true
  def mint(%Item{} = item, _opts) do
    prefix = Settings.doi_prefix()
    endpoint = doi_endpoint()
    username = Settings.doi_username()
    password = Settings.doi_password()

    cond do
      blank?(prefix) ->
        {:error, :missing_prefix}

      blank?(username) or blank?(password) ->
        {:error, :missing_credentials}

      true ->
        doi = build_doi(prefix, item)
        payload = build_payload(doi, item)

        request =
          Req.new(
            url: String.trim_trailing(endpoint, "/") <> "/dois/" <> URI.encode(doi),
            method: :put,
            json: payload,
            auth: {:basic, "#{username}:#{password}"},
            receive_timeout: 15_000
          )

        case Req.request(request) do
          {:ok, %Req.Response{status: status}} when status in 200..299 ->
            {:ok, doi}

          {:ok, %Req.Response{status: status, body: body}} ->
            Logger.warning(
              "DataCite mint failed status=#{status} doi=#{doi} body=#{inspect(body)}"
            )

            {:error, {:datacite_http_error, status}}

          {:error, reason} ->
            Logger.warning("DataCite network error doi=#{doi}: #{inspect(reason)}")
            {:error, {:network_error, reason}}
        end
    end
  end

  defp doi_endpoint, do: Settings.get("doi_endpoint") || @default_endpoint

  defp build_doi(prefix, %Item{} = item) do
    suffix = item.handle || item.id
    "#{prefix}/#{suffix}"
  end

  defp build_payload(doi, %Item{} = item) do
    %{
      data: %{
        type: "dois",
        id: doi,
        attributes: %{
          doi: doi,
          prefix: Settings.doi_prefix(),
          url: item_url(item),
          types: %{
            resourceTypeGeneral: resource_type_general(item),
            resourceType: resource_type(item)
          },
          creators: creators(item),
          titles: [%{title: item.title || "Untitled"}],
          publisher: Settings.get("doi_publisher") || Settings.brand_name(),
          publicationYear: publication_year(item),
          # 'publish' registers + makes findable; 'register' keeps it hidden.
          # Defaults to 'register' so admins can review before public exposure.
          event: "register"
        }
      }
    }
  end

  defp creators(%Item{item_authors: authors}) when is_list(authors) and authors != [] do
    Enum.map(authors, fn a ->
      creator = %{name: a.author_name}

      creator =
        if a.affiliation && a.affiliation != "" do
          Map.put(creator, :affiliation, [%{name: a.affiliation}])
        else
          creator
        end

      if a.orcid && a.orcid != "" do
        name_identifiers = [
          %{
            nameIdentifier: normalize_orcid(a.orcid),
            nameIdentifierScheme: "ORCID",
            schemeUri: "https://orcid.org"
          }
        ]

        Map.put(creator, :nameIdentifiers, name_identifiers)
      else
        creator
      end
    end)
  end

  defp creators(_), do: [%{name: Settings.brand_name()}]

  defp normalize_orcid(value) do
    trimmed = String.trim(value)

    cond do
      String.starts_with?(trimmed, "https://orcid.org/") ->
        trimmed

      Regex.match?(~r/^\d{4}-\d{4}-\d{4}-\d{3}[\dX]$/, trimmed) ->
        "https://orcid.org/" <> trimmed

      true ->
        trimmed
    end
  end

  # Map Kiroku item types to DataCite resourceTypeGeneral. Falls back to Text.
  defp resource_type_general(%Item{item_type: type})
       when type in ~w(thesis undergraduate_thesis masters_thesis doctoral_thesis)a,
       do: "Text"

  defp resource_type_general(%Item{item_type: type})
       when type in ~w(journal_article conference_paper)a,
       do: "Text"

  defp resource_type_general(%Item{item_type: type})
       when type in ~w(dataset software learning_object patent)a,
       do: "Dataset"

  defp resource_type_general(_), do: "Text"

  defp resource_type(%Item{item_type: type}) when is_atom(type), do: Atom.to_string(type)
  defp resource_type(_), do: "Text"

  defp publication_year(%Item{publication_year: year}) when is_integer(year), do: year
  defp publication_year(%Item{published_at: %NaiveDateTime{year: year}}), do: year
  defp publication_year(_), do: DateTime.utc_now().year

  defp item_url(%Item{handle: handle}) when is_binary(handle) do
    KirokuWeb.Endpoint.url() <> "/items/" <> handle
  end

  defp item_url(%Item{id: id}), do: KirokuWeb.Endpoint.url() <> "/items/" <> id

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_), do: false
end
