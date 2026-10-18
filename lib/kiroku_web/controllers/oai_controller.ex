defmodule KirokuWeb.OaiController do
  use KirokuWeb, :controller

  alias Kiroku.Oai.Builder

  # OAI-PMH responses are always HTTP 200 — protocol errors are signalled in
  # the XML body with <error code="...">, not with HTTP status codes (§3.1.2).
  def index(conn, %{"verb" => verb} = params) do
    xml =
      case verb do
        "Identify" -> Builder.identify(params)
        "ListMetadataFormats" -> Builder.list_metadata_formats(params)
        "ListSets" -> Builder.list_sets(params)
        "ListIdentifiers" -> Builder.list_identifiers(params)
        "ListRecords" -> Builder.list_records(params)
        "GetRecord" -> Builder.get_record(params)
        _ -> Builder.error("badVerb", "Illegal OAI verb", params)
      end

    conn
    |> put_resp_content_type("text/xml")
    |> send_resp(200, xml)
  end

  def index(conn, params) do
    conn
    |> put_resp_content_type("text/xml")
    |> send_resp(200, Builder.error("badVerb", "Missing verb parameter", params))
  end
end
