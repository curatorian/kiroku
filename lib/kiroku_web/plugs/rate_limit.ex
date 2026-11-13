defmodule KirokuWeb.Plugs.RateLimit do
  @moduledoc """
  IP-based rate limiting for sensitive endpoints, backed by Hammer (ETS backend).

  Used as a plug on the guest (register / log in / reset password) scope, and
  via `check/3` from controllers and LiveView event handlers — websocket events
  bypass the HTTP pipeline, so brute-force protection must also run there.
  """

  import Plug.Conn

  @defaults [limit: 30, period_ms: 60_000]

  def init(opts), do: Keyword.merge(@defaults, opts)

  def call(conn, opts) do
    key = key(Keyword.fetch!(opts, :bucket), conn)

    case check(key, opts[:limit], opts[:period_ms]) do
      :ok ->
        conn

      {:deny, _retry_after_ms} ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(:too_many_requests, "Too many requests. Please slow down.")
        |> halt()
    end
  end

  @doc "Returns `:ok` when within the limit, `{:deny, retry_after_ms}` otherwise."
  def check(key, limit, period_ms) do
    case Hammer.check_rate(key, period_ms, limit) do
      {:allow, _count} -> :ok
      {:deny, retry_after_ms} -> {:deny, retry_after_ms}
      # Backend unavailable — don't lock users out.
      {:error, _reason} -> :ok
    end
  end

  @doc "Builds a rate-limit key for a conn (uses its remote IP)."
  def key(bucket, %Plug.Conn{} = conn), do: "#{bucket}:#{ip_to_string(conn.remote_ip)}"

  def key(bucket, ip) when is_binary(ip), do: "#{bucket}:#{ip}"

  @doc "Extracts the client IP as a string from LiveView connect info."
  def client_ip(socket) do
    case Phoenix.LiveView.get_connect_info(socket, :peer_data) do
      %{address: address} -> ip_to_string(address)
      _ -> "unknown"
    end
  end

  defp ip_to_string(address), do: address |> :inet.ntoa() |> List.to_string()
end
