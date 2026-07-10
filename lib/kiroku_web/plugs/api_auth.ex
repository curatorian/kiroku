defmodule KirokuWeb.Plugs.ApiAuth do
  @moduledoc """
  Reads an API token from either the `Authorization: Bearer <token>` header
  or the `?token=<token>` query parameter, and populates
  `conn.assigns[:current_user]` when the token is valid.

  Used in the `:authenticated_api` pipeline to gate REST API routes.
  Requests with no token or an invalid token get `current_user: nil`;
  the `RequireApiToken` plug handles the 401 response.
  """

  import Plug.Conn

  alias Kiroku.ApiTokens

  def init(opts), do: opts

  def call(conn, _opts) do
    raw_token = token_from_header(conn) || token_from_query(conn)

    case raw_token do
      nil ->
        assign(conn, :current_user, nil)

      token ->
        case ApiTokens.verify_token(token) do
          {:ok, user} -> assign(conn, :current_user, user)
          {:error, _} -> assign(conn, :current_user, nil)
        end
    end
  end

  defp token_from_header(conn) do
    with [header] <- get_req_header(conn, "authorization"),
         "Bearer " <> token <- header do
      token
    else
      _ -> nil
    end
  end

  defp token_from_query(conn) do
    conn.params["token"]
  end
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
        error:
          "Missing or invalid API token. Supply it via the Authorization: Bearer <token> header or the ?token=<token> query parameter."
      })
      |> halt()
    end
  end
end
