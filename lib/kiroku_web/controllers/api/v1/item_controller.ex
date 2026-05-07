defmodule KirokuWeb.Api.V1.ItemController do
  @moduledoc """
  REST API v1 — Items.

  GET /api/v1/items                  — list published items (paginated)
  GET /api/v1/items/:id              — show a single item with full metadata
  GET /api/v1/items/:id/bitstreams   — list accessible bitstreams for an item

  Supports query params for listing:
    q           — full-text search term
    type        — item_type enum value
    faculty     — faculty filter
    department  — department filter
    year        — publication_year filter (integer)
    collection_id — collection UUID filter
    page        — page number (default 1)
    per_page    — results per page (default 20, max 100)
  """

  use KirokuWeb, :controller

  alias Kiroku.{Repository, Content}

  def index(conn, params) do
    per_page = min(String.to_integer(params["per_page"] || "20"), 100)

    search_params = %{
      term: params["q"],
      item_type: params["type"] && String.to_existing_atom(params["type"]),
      faculty: params["faculty"],
      department: params["department"],
      year: params["year"] && String.to_integer(params["year"]),
      collection_id: params["collection_id"],
      page: String.to_integer(params["page"] || "1"),
      per_page: per_page
    }

    items = Repository.search_items(search_params)
    json(conn, %{data: Enum.map(items, &item_brief_json/1)})
  rescue
    ArgumentError ->
      conn
      |> put_status(:bad_request)
      |> json(%{error: "Invalid query parameter"})
  end

  def show(conn, %{"id" => id}) do
    item = Repository.get_item_with_preloads!(id)

    if item.status == :published and item.discoverable do
      json(conn, %{data: item_full_json(item)})
    else
      conn
      |> put_status(:not_found)
      |> json(%{error: "Item not found"})
    end
  rescue
    Ecto.NoResultsError ->
      conn
      |> put_status(:not_found)
      |> json(%{error: "Item not found"})
  end

  def bitstreams(conn, %{"item_id" => item_id}) do
    item = Repository.get_item!(item_id)

    unless item.status == :published and item.discoverable do
      conn
      |> put_status(:not_found)
      |> json(%{error: "Item not found"})
    else
      current_user = conn.assigns[:current_user]
      bitstreams = Content.list_bitstreams_for_item(item_id)

      accessible =
        Enum.filter(bitstreams, fn bs ->
          Content.accessible?(bs, current_user, item)
        end)

      json(conn, %{data: Enum.map(accessible, &bitstream_json/1)})
    end
  end

  # ── JSON serializers ──────────────────────────────────────────────────────

  defp item_brief_json(item) do
    %{
      id: item.id,
      handle: item.handle,
      title: item.title,
      item_type: item.item_type,
      student_name: item.student_name,
      department: item.department,
      faculty: item.faculty,
      publication_year: item.publication_year,
      published_at: item.published_at,
      language: item.language,
      access_level: item.access_level
    }
  end

  defp item_full_json(item) do
    base = item_brief_json(item)

    Map.merge(base, %{
      title_alt: item.title_alt,
      abstract: item.abstract,
      abstract_alt: item.abstract_alt,
      institution: item.institution,
      degree_level: item.degree_level,
      program_study: item.program_study,
      student_id: item.student_id,
      doi: item.doi,
      issn: item.issn,
      eissn: item.eissn,
      journal_name: item.journal_name,
      volume: item.volume,
      issue: item.issue,
      page_start: item.page_start,
      page_end: item.page_end,
      publisher: item.publisher,
      conference_name: item.conference_name,
      conference_location: item.conference_location,
      subject_classification: item.subject_classification,
      date_issued: item.date_issued,
      collection: collection_brief(item.collection),
      authors: Enum.map(item.item_authors || [], &author_json/1),
      advisors: Enum.map(item.item_advisors || [], &advisor_json/1),
      keywords: Enum.map(item.item_keywords || [], & &1.keyword)
    })
  end

  defp author_json(author) do
    %{
      name: author.author_name,
      name_alt: author.author_name_alt,
      affiliation: author.affiliation,
      orcid: author.orcid,
      sequence: author.sequence
    }
  end

  defp advisor_json(advisor) do
    %{
      name: advisor.advisor_name,
      role: advisor.advisor_role,
      affiliation: advisor.affiliation,
      nidn: advisor.nidn
    }
  end

  defp collection_brief(nil), do: nil

  defp collection_brief(collection) do
    %{
      id: collection.id,
      name: collection.name,
      handle: collection.handle
    }
  end

  defp bitstream_json(bitstream) do
    %{
      id: bitstream.id,
      filename: bitstream.filename,
      bundle_name: bitstream.bundle_name,
      sequence: bitstream.sequence,
      description: bitstream.description,
      mime_type: bitstream.mime_type,
      file_size: bitstream.file_size,
      access_level: bitstream.access_level
    }
  end
end
