defmodule KirokuWeb.SwordV2.DepositController do
  @moduledoc """
  SWORD v2 Collection deposit (Col-IRI) and Statement (SED-IRI) endpoints.

  ## POST /sword-v2/collection/:collection_handle

  Accepts either:
    * `Content-Type: application/atom+xml;type=entry` — metadata-only deposit
    * Multipart (`multipart-related`) — metadata + file content

  Creates a draft item in the target collection. The item's status is
  `:draft` — it goes through the normal review workflow before publication.

  ## GET /sword-v2/statement/:item_handle

  Returns a SWORD v2 Statement describing the item's current lifecycle state.
  """

  use KirokuWeb, :controller

  alias Kiroku.{Repository, Sword}
  alias Kiroku.Access.Authorization

  def deposit(conn, %{"collection_handle" => collection_handle}) do
    user = conn.assigns[:current_user]
    collection = Repository.get_collection_by_handle(collection_handle)

    cond do
      is_nil(collection) ->
        send_sword_error(
          conn,
          404,
          "Collection not found",
          "No collection with handle '#{collection_handle}'"
        )

      not Authorization.can?(user, :create, %Kiroku.Repository.Item{collection_id: collection.id}) ->
        send_sword_error(
          conn,
          403,
          "Forbidden",
          "The authenticated user does not have permission to deposit into this collection"
        )

      true ->
        deposit_into_collection(conn, collection, user)
    end
  end

  def statement(conn, %{"item_handle" => item_handle}) do
    case Repository.get_item_with_preloads(item_handle) do
      nil ->
        send_sword_error(conn, 404, "Item not found", "No item with handle '#{item_handle}'")

      item ->
        xml = Sword.Builder.statement(item)

        conn
        |> put_resp_content_type("application/atom+xml")
        |> send_resp(200, xml)
    end
  end

  # ── Deposit logic ───────────────────────────────────────────────────────────

  defp deposit_into_collection(conn, collection, user) do
    content_type = get_req_header(conn, "content-type") |> List.first() || ""

    cond do
      String.contains?(content_type, "multipart") ->
        deposit_multipart(conn, collection, user)

      String.contains?(content_type, "atom") or String.contains?(content_type, "xml") ->
        deposit_atom_entry(conn, collection, user)

      true ->
        send_sword_error(
          conn,
          415,
          "Unsupported Media Type",
          "Expected application/atom+xml or multipart. Got: #{content_type}"
        )
    end
  end

  defp deposit_atom_entry(conn, collection, user) do
    # For XML content types, Plug.Parsers passes the body through unparsed.
    # Read the raw body directly.
    case read_body(conn) do
      {:ok, body, _conn} when is_binary(body) and byte_size(body) > 0 ->
        do_atom_deposit(conn, collection, user, body)

      _ ->
        send_sword_error(
          conn,
          400,
          "Bad Request",
          "Request body is empty. Send an Atom entry XML document."
        )
    end
  end

  defp do_atom_deposit(conn, collection, user, xml_body) do
    case Sword.AtomParser.parse_entry(xml_body) do
      {:ok, parsed} ->
        attrs =
          Map.merge(parsed, %{
            "collection_id" => collection.id,
            "status" => "draft",
            "actor" => user
          })

        case Repository.create_item(attrs) do
          {:ok, item} ->
            xml = Sword.Builder.deposit_receipt(item)

            conn
            |> put_resp_content_type("application/atom+xml")
            |> send_resp(201, xml)

          {:error, changeset} ->
            send_sword_error(conn, 422, "Validation failed", inspect(changeset.errors))
        end

      {:error, reason} ->
        send_sword_error(conn, 400, "Malformed Atom entry", to_string(reason))
    end
  end

  defp deposit_multipart(conn, collection, user) do
    # For multipart deposits, the Atom entry is in the "atom" part and the
    # file content is in the "payload" part. We create the item from the
    # Atom entry, then (if a file was included) store it as a bitstream.
    atom_part = conn.body_params["atom"] || conn.body_params["entry"]
    file_part = conn.body_params["payload"] || conn.body_params["file"]

    if is_nil(atom_part) or (is_nil(file_part) and map_size(conn.body_params) <= 1) do
      # If no Atom part but we have file params, create a minimal item.
      if file_part do
        create_item_from_file(conn, collection, user, file_part)
      else
        send_sword_error(
          conn,
          400,
          "Bad Request",
          "Multipart deposit must include an 'atom' (or 'entry') part with metadata"
        )
      end
    else
      do_atom_deposit(conn, collection, user, atom_part)
    end
  end

  defp create_item_from_file(conn, collection, user, %Plug.Upload{} = upload) do
    attrs = %{
      "title" => Path.basename(upload.filename, Path.extname(upload.filename)),
      "collection_id" => collection.id,
      "status" => "draft",
      "actor" => user
    }

    case Repository.create_item(attrs) do
      {:ok, item} ->
        # Store the file as an ORIGINAL bitstream.
        key = Kiroku.Storage.Uploader.storage_key(item.id, "ORIGINAL", upload.filename)
        content = File.read!(upload.path)

        case Kiroku.Storage.Uploader.upload(key, content,
               mime_type: upload.content_type || "application/octet-stream"
             ) do
          {:ok, %{path: path, checksum: checksum, size: size}} ->
            Kiroku.Content.create_bitstream(
              Map.merge(Kiroku.Storage.Uploader.record_attrs(), %{
                "item_id" => item.id,
                "filename" => upload.filename,
                "bundle_name" => "ORIGINAL",
                "sequence" => 1,
                "storage_path" => path,
                "mime_type" => upload.content_type || "application/octet-stream",
                "file_size" => size,
                "checksum" => checksum,
                "access_level" => "open"
              })
            )

            xml = Kiroku.Sword.Builder.deposit_receipt(item)

            conn
            |> put_resp_content_type("application/atom+xml")
            |> send_resp(201, xml)

          {:error, reason} ->
            send_sword_error(conn, 500, "File storage failed", inspect(reason))
        end

      {:error, changeset} ->
        send_sword_error(conn, 422, "Validation failed", inspect(changeset.errors))
    end
  end

  defp create_item_from_file(conn, _collection, _user, _file) do
    send_sword_error(
      conn,
      400,
      "Bad Request",
      "File upload must be a multipart/form-data file part"
    )
  end

  defp send_sword_error(conn, status, title, summary) do
    xml = Kiroku.Sword.Builder.error_doc(title, summary)

    conn
    |> put_resp_content_type("application/atom+xml")
    |> send_resp(status, xml)
  end
end
