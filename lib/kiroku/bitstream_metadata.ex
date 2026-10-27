defmodule Kiroku.BitstreamMetadata do
  @moduledoc """
  Derives/prefills bitstream file metadata (mime_type, file_size).

  Legacy imports (MSSQL sync URL bitstreams, SAF packages) historically left
  these columns NULL. This context centralizes the derivation rules:

    * `mime_type` — from the filename extension (never nil afterwards)
    * `file_size` — from local file stat, S3 HEAD, or an HTTP HEAD probe of
      the stored URL; `0` means "externally hosted / unknown size"
  """

  require Logger
  alias Kiroku.Storage.Uploader

  @probe_concurrency 16
  @probe_timeout 10_000

  @doc "Filename-derived mime type — always returns a non-empty string."
  def derive_mime(filename) when is_binary(filename) do
    ext = filename |> Path.extname() |> String.trim_leading(".") |> String.downcase()

    MIME.type(ext) || "application/octet-stream"
  end

  def derive_mime(_), do: "application/octet-stream"

  @doc """
  Determines file size for a bitstream map/struct. Returns `integer` (0 =
  unknown, e.g. externally hosted) or raises for unexpected data problems —
  `fill(Bitstream.t())` never leaves `file_size` NULL.
  """
  def derive_size(%{storage_type: :local, storage_path: path}) when is_binary(path) do
    case File.stat(Path.join("priv/uploads", path)) do
      {:ok, %{size: size}} ->
        size

      _ ->
        Logger.warning("[BitstreamMetadata] local file missing for #{path}")
        0
    end
  end

  def derive_size(%{storage_type: :s3, storage_bucket: bucket, storage_path: path})
      when is_binary(bucket) and is_binary(path) do
    case Uploader.s3_object_size(bucket, path) do
      {:ok, size} ->
        size

      {:error, reason} ->
        Logger.warning("[BitstreamMetadata] S3 HEAD failed for #{path}: #{inspect(reason)}")
        0
    end
  end

  def derive_size(%{storage_type: :url, storage_url: url}) when is_binary(url) do
    case head_url_info(url) do
      {size, _mime} when is_integer(size) ->
        size

      _ ->
        Logger.warning("[BitstreamMetadata] URL HEAD failed for #{url}")
        0
    end
  end

  def derive_size(_), do: 0

  @doc """
  HEAD-probes an absolute URL. Returns `{file_size, mime_type}` — either may
  be nil when the target does not answer. Never raises.
  """
  def head_url_info(url) when is_binary(url) do
    if absolute?(url) do
      case Req.head(url, receive_timeout: @probe_timeout, retry: :transient, redirect: true) do
        {:ok, resp} ->
          length =
            resp.headers |> get_header("content-length") |> parse_int()

          mime =
            resp.headers
            |> get_header("content-type")
            |> case do
              [ct | _] -> ct |> String.split(";") |> List.first()
              _ -> nil
            end

          {length, mime}

        _ ->
          {nil, nil}
      end
    else
      {nil, nil}
    end
  end

  def head_url_info(_), do: {nil, nil}

  @doc "HEAD-probes many URLs concurrently; preserves input order in the result."
  def probe_urls(urls) when is_list(urls) do
    urls
    |> Task.async_stream(&head_url_info/1,
      max_concurrency: @probe_concurrency,
      timeout: :infinity
    )
    |> Enum.map(fn
      {:ok, result} -> result
      {:exit, _} -> {nil, nil}
    end)
  end

  def absolute?(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} -> scheme not in [nil, ""] and host not in [nil, ""]
      _ -> false
    end
  end

  def absolute?(_), do: false

  defp get_header(headers, key) when is_map(headers), do: Map.get(headers, key, [])
  defp get_header(_, _), do: []

  defp parse_int([len | _]) do
    case Integer.parse(len) do
      {size, ""} -> size
      _ -> nil
    end
  end

  defp parse_int(_), do: nil
end
