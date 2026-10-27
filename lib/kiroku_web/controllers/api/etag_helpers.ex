defmodule KirokuWeb.Api.ETagHelpers do
  @moduledoc """
  Cheap ETag / If-None-Match support for rarely-changing list endpoints
  (communities, collections). Tag = MD5 of (count, max_updated_at, scope).

  `respond/3` returns the conn in both outcomes: a 304 when the client tag
  matches, or the rendered response with the ETag set.
  """

  import Plug.Conn

  @doc """
  Compares the request's `If-None-Match` header to an ETag derived from
  `revision`. On miss, `render` is called with the ETag-set conn and its
  result (a conn) is returned. On hit, a 304 conn is returned.
  """
  def respond(conn, revision, render) when is_function(render, 1) do
    etag = etag_value(revision)
    tag_conn = put_cache_headers(conn, etag)

    if stale_check_matches?(tag_conn, etag) do
      send_resp(tag_conn, :not_modified, "")
    else
      render.(tag_conn)
    end
  end

  def etag_value({count, max_ts, scope}) do
    raw = inspect({count, to_string(max_ts), inspect(scope)})
    ~s("#{Base.encode16(:crypto.hash(:md5, raw), case: :lower)}")
  end

  defp put_cache_headers(conn, etag) do
    conn
    |> put_resp_header("etag", etag)
    |> put_resp_header("cache-control", "private, max-age=0, must-revalidate")
  end

  defp stale_check_matches?(conn, etag) do
    case get_req_header(conn, "if-none-match") do
      [client_etag | _] ->
        client_etag == etag or client_etag == "*" or
          String.trim_leading(client_etag, "W/") == etag

      _ ->
        false
    end
  end
end
