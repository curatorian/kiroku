defmodule KirokuWeb.ErrorJSON do
  @moduledoc """
  This module is invoked by your endpoint in case of errors on JSON requests.

  Rendered in the uniform v1 error envelope:

      {"error": "<machine_code>", "message": "<human readable>"}

  See config/config.exs.
  """

  @spec_to_code %{
    400 => "bad_request",
    401 => "unauthorized",
    402 => "payment_required",
    403 => "forbidden",
    404 => "not_found",
    405 => "method_not_allowed",
    406 => "not_acceptable",
    408 => "request_timeout",
    409 => "conflict",
    410 => "gone",
    413 => "payload_too_large",
    415 => "unsupported_media_type",
    422 => "unprocessable_entity",
    429 => "too_many_requests",
    500 => "internal_error",
    501 => "not_implemented",
    502 => "bad_gateway",
    503 => "service_unavailable",
    504 => "gateway_timeout"
  }

  def render(template, _assigns) do
    message = Phoenix.Controller.status_message_from_template(template)
    status = template |> String.replace_suffix(".json", "") |> parse_status()

    case @spec_to_code[status] do
      nil -> %{error: status || "internal_error", message: message}
      code -> %{error: code, message: message}
    end
  end

  defp parse_status(status) when is_binary(status) do
    case Integer.parse(status) do
      {int, ""} -> int
      _ -> nil
    end
  end
end
