defmodule KirokuWeb.OaiController do
  use KirokuWeb, :controller

  alias Kiroku.Oai.Builder

  def index(conn, %{"verb" => verb} = params) do
    xml =
      case verb do
        "Identify" -> Builder.identify()
        "ListMetadataFormats" -> Builder.list_metadata_formats()
        "ListSets" -> Builder.list_sets()
        "ListIdentifiers" -> Builder.list_identifiers(params)
        "ListRecords" -> Builder.list_records(params)
        "GetRecord" -> Builder.get_record(params)
        _ -> Builder.error("badVerb", "Illegal OAI verb")
      end

    conn
    |> put_resp_content_type("text/xml")
    |> send_resp(200, xml)
  end

  def index(conn, _params) do
    conn
    |> put_resp_content_type("text/xml")
    |> send_resp(400, Builder.error("badVerb", "Missing verb parameter"))
  end
end
