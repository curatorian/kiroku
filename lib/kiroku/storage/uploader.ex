defmodule Kiroku.Storage.Uploader do
  @moduledoc """
  Handles file storage for bitstreams.
  Adapter resolved at runtime: DB setting → STORAGE_ADAPTER env var → :local.
  Supports :s3 (AWS S3 or any S3-compatible service) and :local adapters.

  S3 operations use ExAws.S3. Configure credentials via DB settings or env vars:
    AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION, S3_BUCKET, S3_ENDPOINT
  """

  require Logger

  @local_upload_dir "priv/uploads"

  # ── Upload ─────────────────────────────────────────────────────────────────

  @doc """
  Uploads binary content to storage. Returns {:ok, storage_key} | {:error, reason}.
  `key` is the full storage path/key, e.g. "items/abc123/fulltext.pdf"
  """
  def upload(key, content, opts \\ []) do
    mime_type = Keyword.get(opts, :mime_type, "application/octet-stream")

    case adapter() do
      :s3 -> upload_s3(key, content, mime_type)
      :local -> upload_local(key, content)
    end
  end

  # ── Presigned download URL ─────────────────────────────────────────────────

  @doc """
  Returns a time-limited URL for downloading a file.
  For :local adapter, returns a path served by Plug.Static.
  """
  def presign_url(bucket, key, opts \\ []) do
    expires_in = Keyword.get(opts, :expires_in, 3600)

    case adapter() do
      :s3 ->
        cond do
          # Explicit public base URL (includes bucket), e.g. https://cdn.example.com/kiroku-uploads
          url = Kiroku.Settings.storage_public_url() ->
            base = String.trim_trailing(url, "/")
            path = String.trim_leading(key, "/")
            "#{base}/#{path}"

          # Custom S3-compatible endpoint (MinIO, R2, etc.) — public URL is endpoint/bucket/key
          endpoint = Kiroku.Settings.storage_endpoint() ->
            base = String.trim_trailing(endpoint, "/")
            path = String.trim_leading(key, "/")
            "#{base}/#{bucket}/#{path}"

          # Standard AWS — generate a time-limited presigned URL
          true ->
            config = ex_aws_config()
            {:ok, url} = ExAws.S3.presigned_url(config, :get, bucket, key, expires_in: expires_in)
            url
        end

      :local ->
        "/uploads/#{key}"
    end
  end

  # ── Delete ─────────────────────────────────────────────────────────────────

  def delete(bucket, key) do
    case adapter() do
      :s3 ->
        ExAws.S3.delete_object(bucket, key)
        |> ExAws.request(ex_aws_config())
        |> case do
          {:ok, _} ->
            :ok

          {:error, reason} ->
            Logger.error("S3 delete failed bucket=#{bucket} key=#{key}: #{inspect(reason)}")
            {:error, reason}
        end

      :local ->
        path = Path.join(@local_upload_dir, key)
        if File.exists?(path), do: File.rm!(path)
        :ok
    end
  end

  # ── Storage key generation ─────────────────────────────────────────────────

  @doc """
  Generates a storage-key for a new bitstream.
  Format: "items/{item_id}/{bundle_lowercase}/{uuid}{ext}"
  """
  def storage_key(item_id, bundle_name, original_filename) do
    ext = Path.extname(original_filename)
    uuid = Ecto.UUID.generate()
    bundle_str = bundle_name |> to_string() |> String.downcase()
    "items/#{item_id}/#{bundle_str}/#{uuid}#{ext}"
  end

  @doc """
  Returns the `Bitstream` record fields that describe where `upload/3` would
  actually write bytes under the current (or given) adapter.

  Always pair `upload/3` with this so the DB row matches the destination —
  otherwise downloads (BitstreamController) look in the wrong place and 404.

      %{storage_type: :s3, storage_bucket: "kiroku-uploads"} | %{storage_type: :local}
  """
  def record_attrs(adapter \\ adapter()) do
    case adapter do
      :s3 -> %{storage_type: :s3, storage_bucket: Kiroku.Settings.storage_bucket()}
      _ -> %{storage_type: :local}
    end
  end

  # ── Private ────────────────────────────────────────────────────────────────

  defp upload_s3(key, content, mime_type) do
    bucket = Kiroku.Settings.storage_bucket()

    ExAws.S3.put_object(bucket, key, content, content_type: mime_type)
    |> ExAws.request(ex_aws_config())
    |> case do
      {:ok, _} ->
        {:ok, key}

      {:error, reason} ->
        Logger.error("S3 upload failed key=#{key}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp upload_local(key, content) do
    path = Path.join(@local_upload_dir, key)
    path |> Path.dirname() |> File.mkdir_p!()
    File.write!(path, content)
    {:ok, key}
  end

  # Builds an ExAws.Config struct from runtime settings.
  # Supports both standard AWS and S3-compatible services (MinIO, Cloudflare R2, etc.)
  defp ex_aws_config do
    opts = [
      access_key_id: Kiroku.Settings.storage_access_key_id() || "",
      secret_access_key: Kiroku.Settings.storage_secret_access_key() || "",
      region: Kiroku.Settings.storage_region()
    ]

    opts =
      case Kiroku.Settings.storage_endpoint() do
        nil ->
          opts

        endpoint ->
          uri = URI.parse(endpoint)
          scheme = if uri.scheme, do: uri.scheme <> "://", else: "https://"
          port = uri.port || if(uri.scheme == "https", do: 443, else: 80)

          opts
          |> Keyword.put(:host, uri.host)
          |> Keyword.put(:scheme, scheme)
          |> Keyword.put(:port, port)
      end

    ExAws.Config.new(:s3, opts)
  end

  defp adapter, do: Kiroku.Settings.storage_adapter()
end
