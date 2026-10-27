defmodule KirokuWeb.Api.NotFoundController do
  @moduledoc """
  Catch-all for unmatched `/api/v1/*` routes — still answered by Phoenix
  (JSON in the uniform error envelope), never by a proxy-level 404.
  """

  use KirokuWeb, :controller

  def not_found(conn, _params) do
    conn
    |> put_status(:not_found)
    |> json(%{error: "not_found", message: "Not Found"})
  end
end
