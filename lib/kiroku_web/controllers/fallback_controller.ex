defmodule KirokuWeb.FallbackController do
  use Phoenix.Controller, formats: [:json]

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> json(%{error: "Not found"})
  end

  def call(conn, {:error, :unauthorized}) do
    conn
    |> put_status(:forbidden)
    |> json(%{error: "Forbidden"})
  end

  def call(conn, {:error, _reason}) do
    conn
    |> put_status(:internal_server_error)
    |> json(%{error: "Internal server error"})
  end
end
