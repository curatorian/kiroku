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

  alias Kiroku.{Repo, Repository, Content}
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
  POST /api/v1/items — create an item with granular relations.

  Body:
      {
        "item": {
          "title": "...",
          "collection_id": "...",
          "item_type": "skripsi",
          "student_name": "...",
          "status": "submitted",       // optional: "draft" (default) or "submitted"
          ...
        },
        "relations": {                 // optional
          "authors": [
            {"author_name": "...", "sequence": 1, ...}
          ],
          "advisors": [
            {"advisor_name": "...", "advisor_role": "main_advisor", ...}
          ],
          "examiners": [
            {"examiner_name": "...", "sequence": 1, ...}
          ],
          "team_members": [
            {"member_name": "...", "role": "lead_developer", ...}
          ],
          "keywords": ["keyword1", "keyword2"],
          "metadata_extras": [
            {"field_schema": "dc", "field_element": "relation", "field_qualifier": "uri", "field_value": "https://..."}
          ]
        }
      }

  The API user becomes the submitter. Requires `:create` permission.
  Returns the created item with all relations preloaded.
  """
  def create(conn, %{"item" => item_params}) do
    user = conn.assigns[:current_user]

    if Authorization.can?(user, :create, %Item{}) do
      relations = Map.get(conn.params, "relations", %{})
      status = Map.get(item_params, "status", "draft")
      item_params = Map.drop(item_params, ["status", "relations"])
      params = Map.put(item_params, "submitter_id", user.id)

      result =
        Repo.transaction(fn ->
          with {:ok, item} <- Repository.create_item(params),
               :ok <- create_relations(item, relations),
               :ok <- maybe_submit(item, status, user) do
            item
          else
            {:error, changeset} ->
              Repo.rollback(changeset)
          end
        end)

      case result do
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

  defp create_relations(_item, %{} = relations) when relations == %{}, do: :ok

  defp create_relations(item, relations) do
    authors = Map.get(relations, "authors", [])
    advisors = Map.get(relations, "advisors", [])
    examiners = Map.get(relations, "examiners", [])
    team_members = Map.get(relations, "team_members", [])
    keywords = Map.get(relations, "keywords", [])
    metadata_extras = Map.get(relations, "metadata_extras", [])

    with :ok <- insert_each(:author, item, authors),
         :ok <- insert_each(:advisor, item, advisors),
         :ok <- insert_each(:examiner, item, examiners),
         :ok <- insert_each(:team_member, item, team_members),
         :ok <- upsert_keywords(item, keywords),
         :ok <- insert_metadata_extras(item, metadata_extras) do
      :ok
    end
  end

  defp insert_each(:author, item, authors) when is_list(authors) do
    Enum.reduce_while(authors, :ok, fn attrs, _acc ->
      case Repository.create_item_author(Map.put(attrs, "item_id", item.id)) do
        {:ok, _} -> {:cont, :ok}
        {:error, cs} -> {:halt, {:error, cs}}
      end
    end)
  end

  defp insert_each(:advisor, item, advisors) when is_list(advisors) do
    Enum.reduce_while(advisors, :ok, fn attrs, _acc ->
      case Repository.create_item_advisor(Map.put(attrs, "item_id", item.id)) do
        {:ok, _} -> {:cont, :ok}
        {:error, cs} -> {:halt, {:error, cs}}
      end
    end)
  end

  defp insert_each(:examiner, item, examiners) when is_list(examiners) do
    Enum.reduce_while(examiners, :ok, fn attrs, _acc ->
      case Repository.create_item_examiner(Map.put(attrs, "item_id", item.id)) do
        {:ok, _} -> {:cont, :ok}
        {:error, cs} -> {:halt, {:error, cs}}
      end
    end)
  end

  defp insert_each(:team_member, item, team_members) when is_list(team_members) do
    Enum.reduce_while(team_members, :ok, fn attrs, _acc ->
      case Repository.create_item_team_member(Map.put(attrs, "item_id", item.id)) do
        {:ok, _} -> {:cont, :ok}
        {:error, cs} -> {:halt, {:error, cs}}
      end
    end)
  end

  defp upsert_keywords(_item, keywords) when keywords in [nil, []], do: :ok

  defp upsert_keywords(%{id: item_id}, keywords) when is_list(keywords) do
    Repository.upsert_keywords_for_item(item_id, keywords)
    :ok
  end

  defp insert_metadata_extras(_item, extras) when extras in [nil, []], do: :ok

  defp insert_metadata_extras(%{id: item_id}, extras) when is_list(extras) do
    Enum.reduce_while(extras, :ok, fn attrs, _acc ->
      attrs = Map.put(attrs, "item_id", item_id)

      case Repository.put_metadata(
             item_id,
             attrs["field_schema"],
             attrs["field_element"],
             attrs["field_qualifier"],
             attrs["field_value"],
             language: attrs["language"],
             position: attrs["position"] || 0
           ) do
        {:ok, _} -> {:cont, :ok}
        {:error, cs} -> {:halt, {:error, cs}}
      end
    end)
  end

  defp maybe_submit(item, "submitted", _user) do
    case Repository.submit_item(item) do
      {:ok, _} -> :ok
      {:error, :invalid_transition} -> :ok
    end
  end

  defp maybe_submit(_item, _status, _user), do: :ok

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

  # ── Full deposit (item + relations + bitstreams) ────────────────────────────

  @doc """
  POST /api/v1/items/deposit — create an item with metadata, relations, and files.

  Supports two modes:

    1. **Multipart/form-data** (default) — files uploaded as form parts:

        POST /api/v1/items/deposit
        Content-Type: multipart/form-data

        item[title]=...&item[collection_id]=...&item[item_type]=skripsi
        relations[authors][0][author_name]=...
        files[cover][0]=@cover.jpg
        files[fulltext][0]=@paper.pdf
        files[chapters][0]=@ch1.pdf&files[chapters][1]=@ch2.pdf

    2. **JSON with link-based files** — files referenced by URL:

        POST /api/v1/items/deposit
        Content-Type: application/json

        {
          "deposit_type": "link",
          "item": {"title": "...", "collection_id": "...", "item_type": "skripsi"},
          "relations": {"authors": [...], "keywords": [...]},
          "files": {
            "cover": ["https://s3.../cover.jpg"],
            "fulltext": ["https://s3.../paper.pdf"],
            "chapters": ["https://s3.../ch1.pdf", "https://s3.../ch2.pdf"]
          },
          "storage_mode": "download"   // optional: "download" (default) or "reference"
        }

  The `storage_mode` option for link-based deposits:
    - `"download"` (default) — downloads the file and stores it in local/S3 storage
    - `"reference"` — stores the URL as storage_path with storage_type :url
  """
  def deposit(conn, params) do
    user = conn.assigns[:current_user]

    if Authorization.can?(user, :create, %Item{}) do
      content_type = get_req_header(conn, "content-type") |> List.first() || ""

      if conn.params["deposit_type"] == "link" or
           (String.contains?(content_type, "json") and
              not String.contains?(content_type, "multipart")) do
        handle_link_deposit(conn, params, user)
      else
        handle_multipart_deposit(conn, params, user)
      end
    else
      forbidden(conn)
    end
  end

  defp handle_multipart_deposit(conn, %{"item" => item_params} = params, user) do
    relations = Map.get(params, "relations", %{})
    status = Map.get(item_params, "status", "draft")
    item_params = Map.drop(item_params, ["status", "relations"])
    params_with_user = Map.put(item_params, "submitter_id", user.id)
    files = Map.get(params, "files", %{})

    result =
      Repo.transaction(fn ->
        with {:ok, item} <- Repository.create_item(params_with_user),
             :ok <- create_relations(item, relations),
             :ok <- maybe_submit(item, status, user),
             :ok <- upload_multipart_files(item, files) do
          item
        else
          {:error, %Ecto.Changeset{} = cs} -> Repo.rollback(cs)
          {:error, reason} -> Repo.rollback({:upload_error, reason})
        end
      end)

    case result do
      {:ok, item} ->
        item = Repository.get_item_with_preloads!(item.id)

        conn
        |> put_status(:created)
        |> put_resp_header("location", "/api/v1/items/#{item.id}")
        |> json(%{data: item_full_json(item)})

      {:error, %Ecto.Changeset{} = changeset} ->
        unprocessable(conn, changeset)

      {:error, {:upload_error, reason}} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "File upload failed", detail: inspect(reason)})
    end
  end

  defp handle_multipart_deposit(conn, _params, _user),
    do: bad_request(conn, "Missing 'item' parameter")

  defp handle_link_deposit(conn, %{"item" => item_params} = params, user) do
    relations = Map.get(params, "relations", %{})
    status = Map.get(item_params, "status", "draft")
    item_params = Map.drop(item_params, ["status", "relations"])
    params_with_user = Map.put(item_params, "submitter_id", user.id)
    files = Map.get(params, "files", %{})
    storage_mode = Map.get(params, "storage_mode", "download")

    result =
      Repo.transaction(fn ->
        with {:ok, item} <- Repository.create_item(params_with_user),
             :ok <- create_relations(item, relations),
             :ok <- maybe_submit(item, status, user),
             :ok <- upload_link_files(item, files, storage_mode) do
          item
        else
          {:error, %Ecto.Changeset{} = cs} -> Repo.rollback(cs)
          {:error, reason} -> Repo.rollback({:upload_error, reason})
        end
      end)

    case result do
      {:ok, item} ->
        item = Repository.get_item_with_preloads!(item.id)

        conn
        |> put_status(:created)
        |> put_resp_header("location", "/api/v1/items/#{item.id}")
        |> json(%{data: item_full_json(item)})

      {:error, %Ecto.Changeset{} = changeset} ->
        unprocessable(conn, changeset)

      {:error, {:upload_error, reason}} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "File upload failed", detail: inspect(reason)})
    end
  end

  defp handle_link_deposit(conn, _params, _user),
    do: bad_request(conn, "Missing 'item' parameter")

  # ── Multipart file processing ──────────────────────────────────────────────

  @spec upload_multipart_files(Item.t(), map()) :: :ok | {:error, any()}
  defp upload_multipart_files(_item, files) when files == %{}, do: :ok

  defp upload_multipart_files(item, files) do
    upload_specs = upload_specs_for_type(to_string(item.item_type))

    Enum.reduce_while(upload_specs, :ok, fn {field, bundle, start_seq}, _acc ->
      case Map.get(files, to_string(field)) do
        nil ->
          {:cont, :ok}

        entries when is_list(entries) ->
          result =
            entries
            |> Enum.with_index()
            |> Enum.reduce_while(:ok, fn {entry, idx}, _acc ->
              case entry do
                %Plug.Upload{} = upload ->
                  seq = start_seq + idx
                  content = File.read!(upload.path)
                  key = Uploader.storage_key(item.id, bundle, upload.filename)
                  mime = upload.content_type || "application/octet-stream"

                  case Uploader.upload(key, content, mime_type: mime) do
                    {:ok, %{checksum: checksum, size: size}} ->
                      attrs =
                        %{
                          item_id: item.id,
                          filename: upload.filename,
                          bundle_name: bundle,
                          sequence: seq,
                          description: bundle_description(bundle, seq),
                          mime_type: mime,
                          file_size: size,
                          storage_path: key,
                          checksum: checksum,
                          checksum_algorithm: "MD5",
                          access_level: "inherit"
                        }
                        |> Map.merge(Uploader.record_attrs())

                      case Content.create_bitstream(attrs) do
                        {:ok, _} -> {:cont, :ok}
                        {:error, cs} -> {:halt, {:error, cs}}
                      end

                    {:error, reason} ->
                      {:halt, {:error, reason}}
                  end

                _ ->
                  {:halt, {:error, :invalid_upload}}
              end
            end)

          case result do
            :ok -> {:cont, :ok}
            error -> {:halt, error}
          end

        _ ->
          {:cont, :ok}
      end
    end)
  end

  # ── Link-based file processing ─────────────────────────────────────────────

  @spec upload_link_files(Item.t(), map(), String.t()) :: :ok | {:error, any()}
  defp upload_link_files(_item, files, _storage_mode) when files == %{}, do: :ok

  defp upload_link_files(item, files, storage_mode) do
    upload_specs = upload_specs_for_type(to_string(item.item_type))

    Enum.reduce_while(upload_specs, :ok, fn {field, bundle, start_seq}, _acc ->
      case Map.get(files, to_string(field)) do
        nil ->
          {:cont, :ok}

        urls when is_list(urls) ->
          result =
            urls
            |> Enum.with_index()
            |> Enum.reduce_while(:ok, fn {url, idx}, _acc ->
              seq = start_seq + idx

              case download_and_store_url(item.id, bundle, url, seq, storage_mode) do
                :ok -> {:cont, :ok}
                {:error, reason} -> {:halt, {:error, reason}}
              end
            end)

          case result do
            :ok -> {:cont, :ok}
            error -> {:halt, error}
          end

        _ ->
          {:cont, :ok}
      end
    end)
  end

  defp download_and_store_url(item_id, bundle, url, seq, "reference") do
    filename = url |> Path.basename() |> URI.decode() |> Path.basename()
    filename = if filename == "", do: "file_#{seq}", else: filename

    attrs =
      %{
        item_id: item_id,
        filename: filename,
        bundle_name: bundle,
        sequence: seq,
        description: bundle_description(bundle, seq),
        mime_type: MIME.type(filename),
        file_size: 0,
        storage_type: :url,
        storage_path: url,
        checksum: nil,
        checksum_algorithm: nil,
        access_level: "inherit"
      }
      |> Map.merge(Uploader.record_attrs())

    case Content.create_bitstream(attrs) do
      {:ok, _} -> :ok
      {:error, cs} -> {:error, cs}
    end
  end

  defp download_and_store_url(item_id, bundle, url, seq, _storage_mode) do
    case Req.get(url, decode_body: false) do
      {:ok, %{status: 200, body: body} = resp} when is_binary(body) ->
        filename = extract_filename_from_url(url, resp)
        content_type = extract_content_type(resp) || MIME.type(filename)
        key = Uploader.storage_key(item_id, bundle, filename)

        case Uploader.upload(key, body, mime_type: content_type) do
          {:ok, %{checksum: checksum, size: size}} ->
            attrs =
              %{
                item_id: item_id,
                filename: filename,
                bundle_name: bundle,
                sequence: seq,
                description: bundle_description(bundle, seq),
                mime_type: content_type,
                file_size: size,
                storage_path: key,
                checksum: checksum,
                checksum_algorithm: "MD5",
                access_level: "inherit"
              }
              |> Map.merge(Uploader.record_attrs())

            case Content.create_bitstream(attrs) do
              {:ok, _} -> :ok
              {:error, cs} -> {:error, cs}
            end

          {:error, reason} ->
            {:error, reason}
        end

      {:ok, %{status: status}} ->
        {:error, {:http_error, status, url}}

      {:error, reason} ->
        {:error, {:download_failed, url, reason}}
    end
  end

  defp extract_filename_from_url(url, resp) do
    # Try Content-Disposition header first
    content_disp =
      case get_resp_header(resp, "content-disposition") do
        [val | _] -> val
        _ -> nil
      end

    filename =
      case content_disp do
        "attachment" <> _ ->
          ~r/filename="?([^";\s]+)"?/
          |> Regex.run(content_disp)
          |> then(fn
            [_, name] -> name
            _ -> nil
          end)

        _ ->
          nil
      end

    # Fall back to URL path
    filename =
      if filename do
        URI.decode(filename)
      else
        url
        |> URI.parse()
        |> Map.get(:path, "")
        |> Path.basename()
      end

    if filename == "" or filename == "/" do
      "file_#{System.unique_integer([:positive])}"
    else
      filename
    end
  end

  defp extract_content_type(resp) do
    case get_resp_header(resp, "content-type") do
      [ct | _] -> ct |> String.split(";") |> List.first() |> String.trim()
      _ -> nil
    end
  end

  # ── Upload spec helpers ─────────────────────────────────────────────────────

  defp upload_specs_for_type(type) do
    all_specs = [
      {:cover, :THUMBNAIL, 1},
      {:abstract, :ORIGINAL, 1},
      {:fulltext, :ORIGINAL, 2},
      {:chapters, :CHAPTER, 1},
      {:supplemental, :SUPPLEMENTAL, 1},
      {:media, :MEDIA, 1},
      {:source, :SOURCE, 1},
      {:administrative, :ADMINISTRATIVE, 1}
    ]

    keep = KirokuWeb.ItemForm.bundles_for_type(type)

    Enum.filter(all_specs, fn {field, _bundle, _seq} -> field in keep end)
  end

  defp bundle_description(:THUMBNAIL, _), do: "Cover image"
  defp bundle_description(:ORIGINAL, 1), do: "Abstract"
  defp bundle_description(:ORIGINAL, _), do: "Full text"
  defp bundle_description(:CHAPTER, seq), do: "Bab #{seq}"
  defp bundle_description(:SUPPLEMENTAL, _), do: "Supplemental document"
  defp bundle_description(:MEDIA, _), do: "Media file"
  defp bundle_description(:SOURCE, _), do: "Source file"
  defp bundle_description(:ADMINISTRATIVE, _), do: "Administrative document"

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
      status: item.status,
      collection: collection_brief(item.collection),
      authors: Enum.map(item.item_authors || [], &author_json/1),
      advisors: Enum.map(item.item_advisors || [], &advisor_json/1),
      examiners: Enum.map(item.item_examiners || [], &examiner_json/1),
      team_members: Enum.map(item.item_team_members || [], &team_member_json/1),
      keywords: Enum.map(item.item_keywords || [], & &1.keyword),
      metadata_extras: Enum.map(item.metadata_extras || [], &metadata_extra_json/1)
    })
  end

  defp author_json(author) do
    %{
      id: author.id,
      name: author.author_name,
      name_alt: author.author_name_alt,
      affiliation: author.affiliation,
      email: author.email,
      orcid: author.orcid,
      sequence: author.sequence
    }
  end

  defp advisor_json(advisor) do
    %{
      id: advisor.id,
      name: advisor.advisor_name,
      name_alt: advisor.advisor_name_alt,
      role: advisor.advisor_role,
      affiliation: advisor.affiliation,
      nidn: advisor.nidn,
      sequence: advisor.sequence
    }
  end

  defp examiner_json(examiner) do
    %{
      id: examiner.id,
      name: examiner.examiner_name,
      name_alt: examiner.examiner_name_alt,
      affiliation: examiner.affiliation,
      nidn: examiner.nidn,
      sequence: examiner.sequence
    }
  end

  defp team_member_json(member) do
    %{
      id: member.id,
      name: member.member_name,
      name_alt: member.member_name_alt,
      role: member.role,
      student_id: member.student_id,
      affiliation: member.affiliation,
      sequence: member.sequence
    }
  end

  defp metadata_extra_json(extra) do
    %{
      id: extra.id,
      schema: extra.field_schema,
      element: extra.field_element,
      qualifier: extra.field_qualifier,
      value: extra.field_value,
      language: extra.language
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
