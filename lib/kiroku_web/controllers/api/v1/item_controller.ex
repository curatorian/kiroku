defmodule KirokuWeb.Api.V1.ItemController do
  @moduledoc """
  REST API v1 — Items.

  Read:
    GET  /api/v1/items                  — list published items (paginated)
    GET  /api/v1/items/:id              — show a single item with full metadata
    GET  /api/v1/items/:id/bitstreams   — list accessible bitstreams for an item

  Write (API-token-authenticated, authorized via Authorization.can?/3):
    POST  /api/v1/items                 — create a draft item
    PATCH /api/v1/items/:id             — update item metadata
    POST  /api/v1/items/:id/bitstreams  — deposit a file (multipart upload)

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
  alias Kiroku.Repository.Item
  alias Kiroku.Access.Authorization
  alias Kiroku.Storage.Uploader

  @valid_bundles ~w(ORIGINAL THUMBNAIL CHAPTER SUPPLEMENTAL ADMINISTRATIVE LICENSE MEDIA SOURCE)a

  def index(conn, params) do
    per_page = min(String.to_integer(params["per_page"] || "20"), 100)
    scope = Authorization.visibility_scope(conn.assigns[:current_user])

    search_params = %{
      term: params["q"],
      item_type: params["type"] && String.to_existing_atom(params["type"]),
      faculty: params["faculty"],
      department: params["department"],
      year: params["year"] && String.to_integer(params["year"]),
      collection_id: params["collection_id"],
      page: String.to_integer(params["page"] || "1"),
      per_page: per_page,
      scope: scope
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

    if item.status == :published and item.discoverable and
         Authorization.can?(conn.assigns[:current_user], :read, item) do
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

  # ── Write endpoints ───────────────────────────────────────────────────────

  @doc """
  POST /api/v1/items — create a draft item.

  Body: `{"item": {"title": "...", "collection_id": "...", ...}}`.
  The API user becomes the submitter. Requires `:create` permission.
  """
  def create(conn, %{"item" => item_params}) do
    user = conn.assigns[:current_user]

    if Authorization.can?(user, :create, %Item{}) do
      params = Map.put(item_params, "submitter_id", user.id)

      case Repository.create_item(params) do
        {:ok, item} ->
          item = Repository.get_item_with_preloads!(item.id)

          conn
          |> put_status(:created)
          |> put_resp_header("location", "/api/v1/items/#{item.id}")
          |> json(%{data: item_full_json(item)})

        {:error, changeset} ->
          unprocessable(conn, changeset)
      end
    else
      forbidden(conn)
    end
  end

  def create(conn, _params), do: bad_request(conn, "Missing 'item' parameter")

  @doc """
  PATCH /api/v1/items/:id — update item metadata.

  Body: `{"item": {...}}`. Requires `:update` permission on the item.
  """
  def update(conn, %{"id" => id, "item" => item_params}) do
    user = conn.assigns[:current_user]

    with {:ok, item} <- fetch_item(id),
         true <- Authorization.can?(user, :update, item) do
      case Repository.update_item(item, item_params) do
        {:ok, _} ->
          json(conn, %{data: item_full_json(Repository.get_item_with_preloads!(id))})

        {:error, changeset} ->
          unprocessable(conn, changeset)
      end
    else
      {:error, :not_found} -> not_found(conn, "Item not found")
      false -> forbidden(conn)
    end
  end

  def update(conn, _params), do: bad_request(conn, "Missing 'item' parameter")

  @doc """
  POST /api/v1/items/:id/bitstreams — deposit a file (multipart/form-data).

  Form fields: `file` (required upload), plus optional `bundle_name`,
  `description`, `sequence`, `access_level`. Requires `:update` permission.
  """
  def deposit_bitstream(conn, %{"item_id" => id, "file" => %Plug.Upload{} = upload}) do
    user = conn.assigns[:current_user]

    with {:ok, item} <- fetch_item(id),
         true <- Authorization.can?(user, :update, item),
         {:ok, bundle} <- parse_bundle(conn.params["bundle_name"]) do
      deposit(conn, item, upload, bundle)
    else
      {:error, :not_found} -> not_found(conn, "Item not found")
      {:error, :invalid_bundle} -> bad_request(conn, "Invalid bundle_name")
      false -> forbidden(conn)
    end
  end

  def deposit_bitstream(conn, _params), do: bad_request(conn, "Missing 'file' upload")

  defp deposit(conn, item, %Plug.Upload{} = upload, bundle) do
    content = File.read!(upload.path)
    key = Uploader.storage_key(item.id, bundle, upload.filename)

    case Uploader.upload(key, content,
           mime_type: upload.content_type || "application/octet-stream"
         ) do
      {:ok, %{checksum: checksum, size: size}} ->
        attrs =
          %{
            item_id: item.id,
            filename: upload.filename,
            bundle_name: bundle,
            sequence: parse_seq(conn.params["sequence"]),
            description: conn.params["description"],
            mime_type: upload.content_type,
            file_size: size,
            storage_path: key,
            checksum: checksum,
            checksum_algorithm: "MD5",
            access_level: conn.params["access_level"] || "inherit"
          }
          |> Map.merge(Uploader.record_attrs())

        case Content.create_bitstream(attrs) do
          {:ok, bs} ->
            conn |> put_status(:created) |> json(%{data: bitstream_json(bs)})

          {:error, changeset} ->
            unprocessable(conn, changeset)
        end

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Upload failed", detail: inspect(reason)})
    end
  end

  # ── Helpers ───────────────────────────────────────────────────────────────

  defp fetch_item(id) do
    case Repository.get_item_with_preloads(id) do
      nil -> {:error, :not_found}
      item -> {:ok, item}
    end
  end

  defp parse_bundle(nil), do: {:ok, :ORIGINAL}

  defp parse_bundle(str) when is_binary(str) do
    up = String.upcase(str)

    if up in Enum.map(@valid_bundles, &Atom.to_string/1) do
      {:ok, String.to_existing_atom(up)}
    else
      {:error, :invalid_bundle}
    end
  end

  defp parse_seq(nil), do: 1

  defp parse_seq(str) when is_binary(str) do
    case Integer.parse(str) do
      {n, ""} -> n
      _ -> 1
    end
  end

  defp parse_seq(n) when is_integer(n), do: n

  defp forbidden(conn), do: conn |> put_status(:forbidden) |> json(%{error: "Forbidden"})

  defp not_found(conn, msg), do: conn |> put_status(:not_found) |> json(%{error: msg})

  defp bad_request(conn, msg), do: conn |> put_status(:bad_request) |> json(%{error: msg})

  defp unprocessable(conn, changeset) do
    conn |> put_status(:unprocessable_entity) |> json(%{errors: error_map(changeset)})
  end

  defp error_map(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc ->
        String.replace(acc, "%{#{k}}", to_string(v))
      end)
    end)
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
