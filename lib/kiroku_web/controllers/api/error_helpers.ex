defmodule KirokuWeb.Api.ErrorHelpers do
  @moduledoc """
  Uniform error envelope for the REST API v1 surface.

  Every non-2xx response is `application/json` of the shape:

      {"error": "<machine_code>", "message": "<human readable>"}

  Validation failures add a `fields` map:

      {"error": "validation_error", "message": "...", "fields": {"title": ["can't be blank"]}}
  """

  import Phoenix.Controller, only: [json: 2]
  import Plug.Conn

  @doc "Renders the uniform error envelope with the given status, machine code and human message."
  def error(conn, status, code, message, extra \\ %{}) do
    base = %{error: code, message: message}
    payload = if extra == %{}, do: base, else: Map.merge(base, Map.new(extra))

    conn
    |> put_status(status)
    |> json(payload)
  end

  def bad_request(conn, message \\ "Bad request") do
    error(conn, :bad_request, "bad_request", message)
  end

  def forbidden(conn, message \\ "Forbidden") do
    error(conn, :forbidden, "forbidden", message)
  end

  def not_found(conn, message \\ "Not found") do
    error(conn, :not_found, "not_found", message)
  end

  def unprocessable(conn, changeset) do
    error(conn, :unprocessable_entity, "validation_error", "Validation failed",
      fields: error_fields(changeset)
    )
  end

  def error_fields(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc ->
        String.replace(acc, "%{#{k}}", to_string(v))
      end)
    end)
  end
end
