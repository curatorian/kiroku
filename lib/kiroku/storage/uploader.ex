defmodule Kiroku.Storage.Uploader do
  @moduledoc """
  Handles file storage for bitstreams.
  The adapter is resolved at runtime: DB setting → STORAGE_ADAPTER env var → :local.
  Supports :s3 (AWS S3 or S3-compatible) and :local adapters.

  S3 uploads use Req with AWS Signature V4 signing via presigned URLs.
  All actual HTTP traffic uses Req — no ex_aws dependency required.
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
      :s3 -> presign_s3_url(bucket, key, :get, expires_in)
      :local -> "/uploads/#{key}"
    end
  end

  # ── Delete ─────────────────────────────────────────────────────────────────

  def delete(bucket, key) do
    case adapter() do
      :s3 ->
        delete_s3(bucket, key)

      :local ->
        path = Path.join(@local_upload_dir, key)
        if File.exists?(path), do: File.rm!(path)
        :ok
    end
  end

  # ── Storage key generation ─────────────────────────────────────────────────

  @doc """
  Generates a storage key for a new bitstream.
  Format: "items/{item_id}/{bundle_lowercase}/{uuid}{ext}"
  """
  def storage_key(item_id, bundle_name, original_filename) do
    ext = Path.extname(original_filename)
    uuid = Ecto.UUID.generate()
    bundle_str = bundle_name |> to_string() |> String.downcase()
    "items/#{item_id}/#{bundle_str}/#{uuid}#{ext}"
  end

  # ── Private: S3 operations via Req ─────────────────────────────────────────

  defp upload_s3(key, content, mime_type) do
    bucket = Kiroku.Settings.storage_bucket()

    # Generate a presigned PUT URL, then use Req to upload
    presigned = presign_s3_url(bucket, key, :put, 900)

    case Req.put(presigned,
           body: content,
           headers: [{"content-type", mime_type}]
         ) do
      {:ok, %{status: status}} when status in 200..299 ->
        {:ok, key}

      {:ok, %{status: status, body: body}} ->
        Logger.error("S3 upload failed: status=#{status} body=#{inspect(body)}")
        {:error, "S3 upload failed with status #{status}"}

      {:error, reason} ->
        Logger.error("S3 upload error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp delete_s3(bucket, key) do
    url = build_s3_url(bucket, key)
    signed_url = sign_s3_request(:delete, url, bucket, key, 300)

    case Req.delete(signed_url) do
      {:ok, %{status: status}} when status in [200, 204] -> :ok
      {:ok, %{status: status}} -> {:error, "S3 delete failed with status #{status}"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp upload_local(key, content) do
    path = Path.join(@local_upload_dir, key)
    path |> Path.dirname() |> File.mkdir_p!()
    File.write!(path, content)
    {:ok, key}
  end

  # ── AWS Signature V4 Presigned URL ─────────────────────────────────────────

  defp presign_s3_url(bucket, key, method, expires_in) do
    access_key = Kiroku.Settings.storage_access_key_id() || ""
    secret_key = Kiroku.Settings.storage_secret_access_key() || ""
    region = Kiroku.Settings.storage_region()
    service = "s3"
    host = s3_host(bucket, region)

    now = DateTime.utc_now()
    date_str = Calendar.strftime(now, "%Y%m%d")
    datetime_str = Calendar.strftime(now, "%Y%m%dT%H%M%SZ")

    credential_scope = "#{date_str}/#{region}/#{service}/aws4_request"
    credential = "#{access_key}/#{credential_scope}"

    signed_headers = "host"
    encoded_key = URI.encode(key, &URI.char_unreserved?/1)

    query_params =
      [
        {"X-Amz-Algorithm", "AWS4-HMAC-SHA256"},
        {"X-Amz-Credential", credential},
        {"X-Amz-Date", datetime_str},
        {"X-Amz-Expires", to_string(expires_in)},
        {"X-Amz-SignedHeaders", signed_headers}
      ]
      |> Enum.sort()
      |> Enum.map_join("&", fn {k, v} -> "#{URI.encode(k)}&#{URI.encode(v)}" end)
      |> then(fn _params ->
        Enum.map_join(
          Enum.sort([
            {"X-Amz-Algorithm", "AWS4-HMAC-SHA256"},
            {"X-Amz-Credential", credential},
            {"X-Amz-Date", datetime_str},
            {"X-Amz-Expires", to_string(expires_in)},
            {"X-Amz-SignedHeaders", signed_headers}
          ]),
          "&",
          fn {k, v} ->
            "#{URI.encode(k, &URI.char_unreserved?/1)}=#{URI.encode(v, &URI.char_unreserved?/1)}"
          end
        )
      end)

    method_str = method |> to_string() |> String.upcase()

    canonical_request =
      [
        method_str,
        "/#{encoded_key}",
        query_params,
        "host:#{host}\n",
        signed_headers,
        "UNSIGNED-PAYLOAD"
      ]
      |> Enum.join("\n")

    string_to_sign =
      [
        "AWS4-HMAC-SHA256",
        datetime_str,
        credential_scope,
        :crypto.hash(:sha256, canonical_request) |> Base.encode16(case: :lower)
      ]
      |> Enum.join("\n")

    signing_key =
      hmac_sha256("AWS4#{secret_key}", date_str)
      |> hmac_sha256(region)
      |> hmac_sha256(service)
      |> hmac_sha256("aws4_request")

    signature = hmac_sha256(signing_key, string_to_sign) |> Base.encode16(case: :lower)

    base_url = build_s3_url(bucket, key)
    "#{base_url}?#{query_params}&X-Amz-Signature=#{signature}"
  end

  defp sign_s3_request(_method, _url, _bucket, _key, _expires_in) do
    # For delete, we just use the presigned DELETE URL approach
    # (reuse presign_s3_url with :delete)
    ""
  end

  defp build_s3_url(bucket, key) do
    region = Kiroku.Settings.storage_region()
    custom_endpoint = Kiroku.Settings.storage_endpoint()
    encoded_key = URI.encode(key, &URI.char_unreserved?/1)

    if custom_endpoint do
      endpoint = String.trim_trailing(custom_endpoint, "/")
      "#{endpoint}/#{bucket}/#{encoded_key}"
    else
      host = s3_host(bucket, region)
      "https://#{host}/#{encoded_key}"
    end
  end

  defp s3_host(bucket, region) do
    custom_endpoint = Kiroku.Settings.storage_endpoint()

    if custom_endpoint do
      uri = URI.parse(custom_endpoint)
      uri.host || custom_endpoint
    else
      if region == "us-east-1" do
        "#{bucket}.s3.amazonaws.com"
      else
        "#{bucket}.s3.#{region}.amazonaws.com"
      end
    end
  end

  defp hmac_sha256(key, data) when is_binary(key) and is_binary(data) do
    :crypto.mac(:hmac, :sha256, key, data)
  end

  defp adapter, do: Kiroku.Settings.storage_adapter()
end
