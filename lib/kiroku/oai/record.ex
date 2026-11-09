defmodule Kiroku.Oai.Record do
  @moduledoc """
  Projects a preloaded `Kiroku.Repository.Item` into an OAI-PMH record —
  header (identifier / datestamp / setSpecs) plus Dublin Core fields.

  Consumed by `Kiroku.Oai.Builder` for the machine XML responses and by the
  human-readable `/oai` LiveView. Only public items reach this module:
  `Repository.oai_items/1` already filters to `:published`, `discoverable`,
  `:open`.

  Hygiene rules:
  * Literal "NULL" strings (a legacy MSSQL import artifact) are dropped from
    every field, never emitted as content.
  * The primary author (lowest `sequence`) is `dc:creator`; additional
    authors are demoted to `dc:contributor`.
  * `dc:date` carries the publication year — the record's modification time
    belongs in the header `datestamp`, not in `dc:date`.
  """

  alias Kiroku.Settings

  defstruct [
    :identifier,
    :datestamp,
    :set_specs,
    :title,
    :rights,
    creators: [],
    contributors: [],
    subjects: [],
    sources: [],
    descriptions: [],
    identifiers: [],
    types: [],
    languages: [],
    dates: [],
    publishers: []
  ]

  @null_values ~w(null)

  @doc "Projects many items (preserving order) for ListRecords responses."
  def for_items(items), do: Enum.map(items, &for_item/1)

  @doc "Projects one item for GetRecord / single-record rendering."
  def for_item(item) do
    %__MODULE__{
      identifier: oai_identifier(item),
      datestamp: datestamp(item),
      set_specs: set_specs(item),
      title: item.title,
      creators: creators(item),
      contributors: contributors(item),
      subjects: subjects(item),
      sources: non_nil([item.journal_name, item.conference_name]),
      descriptions: non_nil([item.abstract, item.abstract_alt]),
      identifiers: record_identifiers(item),
      types: non_nil([to_s(item.item_type)]),
      languages: non_nil([to_s(item.language)]),
      dates: dates(item),
      publishers: non_nil([item.publisher]),
      rights: rights(item)
    }
  end

  # ── Header ────────────────────────────────────────────────────────────────

  defp oai_identifier(item), do: Settings.oai_repo_identifier() <> ":" <> item.id

  defp datestamp(%{updated_at: %NaiveDateTime{} = updated_at}),
    do: NaiveDateTime.to_iso8601(updated_at) <> "Z"

  defp datestamp(_), do: nil

  # §2.5/§2.6: headers MUST include the item's set memberships — the owning
  # collection and its parent community.
  defp set_specs(%{collection: %{id: collection_id, community_id: community_id}})
       when is_binary(collection_id) do
    ["col_" <> collection_id, "com_" <> community_id]
  end

  defp set_specs(_), do: []

  # ── Dublin Core fields ────────────────────────────────────────────────────

  defp creators(%{item_authors: authors}) when is_list(authors) do
    case valid_names(authors) do
      [primary | _] -> [primary]
      [] -> []
    end
  end

  defp creators(_), do: []

  defp contributors(%{item_authors: authors}) when is_list(authors) do
    case valid_names(authors) do
      [_primary | rest] -> rest
      [] -> []
    end
  end

  defp contributors(_), do: []

  # Sorted by sequence so the primary author is deterministic.
  defp valid_names(authors) do
    authors
    |> Enum.sort_by(& &1.sequence)
    |> Enum.map(& &1.author_name)
    |> Enum.filter(&meaningful?/1)
  end

  defp subjects(%{item_keywords: keywords}) when is_list(keywords) do
    keywords |> Enum.map(& &1.keyword) |> Enum.filter(&meaningful?/1)
  end

  defp subjects(_), do: []

  defp record_identifiers(item) do
    url = KirokuWeb.Endpoint.url() <> "/items/#{item.handle}"

    case item.doi do
      doi when is_binary(doi) and doi != "" -> [url, "https://doi.org/" <> doi]
      _ -> [url]
    end
  end

  # dc:date = publication year, omitted entirely when unknown.
  defp dates(%{publication_year: year}) when is_integer(year), do: [to_string(year)]
  defp dates(_), do: []

  defp rights(%{access_level: :open}), do: "info:eu-repo/semantics/openAccess"
  defp rights(_), do: "info:eu-repo/semantics/restrictedAccess"

  # ── Helpers ───────────────────────────────────────────────────────────────

  defp non_nil(values), do: Enum.filter(values, &meaningful?/1)

  defp to_s(nil), do: nil
  defp to_s(value) when is_atom(value), do: Atom.to_string(value)
  defp to_s(value) when is_binary(value), do: value

  # Drops blanks and literal "NULL"/"null" values from legacy imports.
  defp meaningful?(value) when is_binary(value) do
    trimmed = String.trim(value)
    trimmed != "" and String.downcase(trimmed) not in @null_values
  end

  defp meaningful?(_), do: false
end
