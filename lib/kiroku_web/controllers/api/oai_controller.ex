defmodule KirokuWeb.Api.OaiController do
  @moduledoc """
  The machine-facing OAI-PMH endpoint.

  This is the endpoint harvesters talk to: it always answers with OAI-PMH 2.0
  XML (`text/xml`), never HTML. Protocol-level errors are reported in the XML
  body via `<error code="...">` with HTTP 200, per OAI-PMH §3.1.2.

  The human-readable counterpart lives at `/oai` (`KirokuWeb.OaiLive`).
  """

  use KirokuWeb, :controller

  alias Kiroku.Oai.Builder

  # OAI-PMH responses are always HTTP 200 — protocol errors are signalled in
  # the XML body with <error code="...">, not with HTTP status codes (§3.1.2).
  def index(conn, params) do
    # §3.2: the <request> element must carry the base URL of the request that
    # produced the response — that is /api/oai, not the /oai UI page.
    Builder.put_endpoint("/api/oai")

    conn
    |> put_resp_content_type("text/xml", "utf-8")
    |> send_resp(200, Builder.raw_xml(params))
  end
end
