defmodule KirokuWeb.Plugs.ApiAuth do
  @moduledoc """
  Reads an API token from the `Authorization: Bearer <token>` header and
  populates `conn.assigns[:current_user]` when the token is valid.

  Used in the `:authenticated_api` pipeline to gate REST API routes.
  Requests with no token leave `conn.assigns[:current_user]` untouched (so
  session/browser users and anonymous access keep working); an invalid token
  sets `current_user: nil`. The `RequireApiToken` plug handles the 401
  response for routes that require a token.

  Kiosk `:device` tokens are scoped to the kiosk endpoints
  (`/api/v1/kiosks/*`, `/api/v1/events`) and do not authenticate any other
  route.
  """

  import Plug.Conn

  alias Kiroku.ApiTokens

  def init(opts), do: opts

  def call(conn, _opts) do
    case token_from_header(conn) do
      nil ->
        # Leave conn.assigns[:current_user] untouched so session/browser users
        # (and anonymous access) keep working when no token is supplied.
        conn

      token ->
        case ApiTokens.verify_token(token) do
          {:ok, user, api_token} ->
            if device_token_allowed?(conn, api_token) do
              conn
              |> assign(:current_user, user)
              |> assign(:api_token, api_token)
            else
              assign(conn, :current_user, nil)
            end

          {:error, _} ->
            throttle_invalid_token(conn)
        end
    end
  end

  # Slow down brute-force attempts against the token space: after 30 invalid
  # tokens within 5 minutes from one IP, answer 429 without touching the DB.
  defp throttle_invalid_token(conn) do
    conn = assign(conn, :current_user, nil)

    case Hammer.check_rate("api_auth_fail:#{ip(conn)}", 300_000, 30) do
      {:allow, _count} ->
        conn

      {:deny, _retry_after_ms} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          :too_many_requests,
          ~s({"error":"too_many_requests","message":"Too many invalid API token attempts."})
        )
        |> halt()

      {:error, _reason} ->
        conn
    end
  end

  defp ip(conn) do
    conn.remote_ip |> :inet.ntoa() |> List.to_string()
  end

  defp token_from_header(conn) do
    with [header] <- get_req_header(conn, "authorization"),
         "Bearer " <> token <- header do
      token
    else
      _ -> nil
    end
  end

  # Device (kiosk) tokens may only authenticate the kiosk endpoints; user
  # tokens work everywhere. Device tokens in the wild must not grant access to
  # item/community/collection writes.
  defp device_token_allowed?(conn, %{token_type: :device}) do
    kiosk_path?(conn.path_info)
  end

  defp device_token_allowed?(_conn, _api_token), do: true

  defp kiosk_path?(["api", "v1", "kiosks" | _]), do: true
  defp kiosk_path?(["api", "v1", "events" | _]), do: true
  defp kiosk_path?(_), do: false
end

defmodule KirokuWeb.Plugs.RequireApiToken do
  @moduledoc """
  Halts the connection with a 401 JSON error when no valid API token
  was supplied. Must run after `ApiAuth`.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  def init(opts), do: opts

  def call(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{
        error: "unauthorized",
        message:
          "Missing or invalid API token. Supply it via the Authorization: Bearer <token> header."
      })
      |> halt()
    end
  end
end
