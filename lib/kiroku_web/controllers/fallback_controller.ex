defmodule KirokuWeb.FallbackController do
  use Phoenix.Controller, formats: [:json]

  import KirokuWeb.Api.ErrorHelpers

  def call(conn, {:error, :not_found}) do
    not_found(conn, "Not found")
  end

  def call(conn, {:error, :unauthorized}) do
    forbidden(conn, "Forbidden")
  end

  def call(conn, {:error, _reason}) do
    conn
    |> put_status(:internal_server_error)
    |> json(%{error: "internal_error", message: "Internal server error"})
  end
end
