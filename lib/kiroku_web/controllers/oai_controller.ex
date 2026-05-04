defmodule KirokuWeb.OaiController do
  use KirokuWeb, :controller

  alias Kiroku.{Repo, Repository}

  @repo_name "Kiroku Institutional Repository"
  @repo_identifier "oai:kiroku.ac.id"
  @admin_email "admin@kiroku.ac.id"
  @metadata_formats [
    %{
      prefix: "oai_dc",
      schema: "http://www.openarchives.org/OAI/2.0/oai_dc.xsd",
      namespace: "http://www.openarchives.org/OAI/2.0/oai_dc/"
    }
  ]

  def index(conn, %{"verb" => verb} = params) do
    {status, body} = handle_verb(verb, params)

    conn
    |> put_resp_content_type("text/xml")
    |> send_resp(status, body)
  end

  def index(conn, _params) do
    conn
    |> put_resp_content_type("text/xml")
    |> send_resp(400, error_response("badVerb", "Missing verb parameter"))
  end

  defp handle_verb("Identify", _params) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    body = """
    <?xml version="1.0" encoding="UTF-8"?>
    <OAI-PMH xmlns="http://www.openarchives.org/OAI/2.0/"
             xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
             xsi:schemaLocation="http://www.openarchives.org/OAI/2.0/ http://www.openarchives.org/OAI/2.0/OAI-PMH.xsd">
      <responseDate>#{now}</responseDate>
      <request verb="Identify">#{base_url()}/oai</request>
      <Identify>
        <repositoryName>#{@repo_name}</repositoryName>
        <baseURL>#{base_url()}/oai</baseURL>
        <protocolVersion>2.0</protocolVersion>
        <adminEmail>#{@admin_email}</adminEmail>
        <earliestDatestamp>2020-01-01T00:00:00Z</earliestDatestamp>
        <deletedRecord>no</deletedRecord>
        <granularity>YYYY-MM-DDThh:mm:ssZ</granularity>
      </Identify>
    </OAI-PMH>
    """

    {200, body}
  end

  defp handle_verb("ListMetadataFormats", _params) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    formats =
      Enum.map_join(@metadata_formats, "\n", fn f ->
        """
            <metadataFormat>
              <metadataPrefix>#{f.prefix}</metadataPrefix>
              <schema>#{f.schema}</schema>
              <metadataNamespace>#{f.namespace}</metadataNamespace>
            </metadataFormat>
        """
      end)

    body = """
    <?xml version="1.0" encoding="UTF-8"?>
    <OAI-PMH xmlns="http://www.openarchives.org/OAI/2.0/"
             xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
             xsi:schemaLocation="http://www.openarchives.org/OAI/2.0/ http://www.openarchives.org/OAI/2.0/OAI-PMH.xsd">
      <responseDate>#{now}</responseDate>
      <request verb="ListMetadataFormats">#{base_url()}/oai</request>
      <ListMetadataFormats>
        #{formats}
      </ListMetadataFormats>
    </OAI-PMH>
    """

    {200, body}
  end

  defp handle_verb("ListRecords", %{"metadataPrefix" => "oai_dc"} = params) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()
    items = Repository.list_published_items()
    records = Enum.map_join(items, "\n", &item_to_oai_dc/1)

    from_date = Map.get(params, "from", "")
    until_date = Map.get(params, "until", "")

    body = """
    <?xml version="1.0" encoding="UTF-8"?>
    <OAI-PMH xmlns="http://www.openarchives.org/OAI/2.0/"
             xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
             xsi:schemaLocation="http://www.openarchives.org/OAI/2.0/ http://www.openarchives.org/OAI/2.0/OAI-PMH.xsd">
      <responseDate>#{now}</responseDate>
      <request verb="ListRecords" metadataPrefix="oai_dc" from="#{from_date}" until="#{until_date}">#{base_url()}/oai</request>
      <ListRecords>
        #{records}
      </ListRecords>
    </OAI-PMH>
    """

    {200, body}
  end

  defp handle_verb("ListRecords", _params) do
    {422, error_response("cannotDisseminateFormat", "Unsupported metadata format")}
  end

  defp handle_verb("GetRecord", %{"metadataPrefix" => "oai_dc", "identifier" => identifier}) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()
    item_id = String.replace(identifier, "#{@repo_identifier}:", "")

    case Repo.get(Kiroku.Repository.Item, item_id) do
      nil ->
        {422, error_response("idDoesNotExist", "Unknown identifier")}

      item ->
        item = Repository.get_item_with_preloads!(item.id)

        body = """
        <?xml version="1.0" encoding="UTF-8"?>
        <OAI-PMH xmlns="http://www.openarchives.org/OAI/2.0/"
                 xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
                 xsi:schemaLocation="http://www.openarchives.org/OAI/2.0/ http://www.openarchives.org/OAI/2.0/OAI-PMH.xsd">
          <responseDate>#{now}</responseDate>
          <request verb="GetRecord" identifier="#{identifier}" metadataPrefix="oai_dc">#{base_url()}/oai</request>
          <GetRecord>
            #{item_to_oai_dc(item)}
          </GetRecord>
        </OAI-PMH>
        """

        {200, body}
    end
  end

  defp handle_verb("GetRecord", _params) do
    {422, error_response("badArgument", "Missing required arguments")}
  end

  defp handle_verb("ListIdentifiers", %{"metadataPrefix" => "oai_dc"}) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()
    items = Repository.list_published_items()

    headers =
      Enum.map_join(items, "\n", fn item ->
        datestamp = datestamp(item.published_at)

        """
            <header>
              <identifier>#{@repo_identifier}:#{item.id}</identifier>
              <datestamp>#{datestamp}</datestamp>
            </header>
        """
      end)

    body = """
    <?xml version="1.0" encoding="UTF-8"?>
    <OAI-PMH xmlns="http://www.openarchives.org/OAI/2.0/"
             xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
             xsi:schemaLocation="http://www.openarchives.org/OAI/2.0/ http://www.openarchives.org/OAI/2.0/OAI-PMH.xsd">
      <responseDate>#{now}</responseDate>
      <request verb="ListIdentifiers" metadataPrefix="oai_dc">#{base_url()}/oai</request>
      <ListIdentifiers>
        #{headers}
      </ListIdentifiers>
    </OAI-PMH>
    """

    {200, body}
  end

  defp handle_verb("ListIdentifiers", _params) do
    {422, error_response("cannotDisseminateFormat", "Unsupported metadata format")}
  end

  defp handle_verb(_verb, _params) do
    {422, error_response("badVerb", "Illegal OAI verb")}
  end

  defp item_to_oai_dc(item) do
    datestamp = datestamp(item.published_at)

    """
        <record>
          <header>
            <identifier>#{@repo_identifier}:#{item.id}</identifier>
            <datestamp>#{datestamp}</datestamp>
          </header>
          <metadata>
            <oai_dc:dc xmlns:oai_dc="http://www.openarchives.org/OAI/2.0/oai_dc/"
                       xmlns:dc="http://purl.org/dc/elements/1.1/"
                       xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
                       xsi:schemaLocation="http://www.openarchives.org/OAI/2.0/oai_dc/ http://www.openarchives.org/OAI/2.0/oai_dc.xsd">
              <dc:title>#{xml_escape(item.title)}</dc:title>
              #{authors_dc(item)}
              <dc:date>#{datestamp}</dc:date>
              #{if item.abstract, do: "<dc:description>#{xml_escape(item.abstract)}</dc:description>", else: ""}
              #{if item.doi, do: "<dc:identifier>#{xml_escape(item.doi)}</dc:identifier>", else: ""}
              <dc:type>#{item.item_type}</dc:type>
              <dc:language>#{item.language || "id"}</dc:language>
            </oai_dc:dc>
          </metadata>
        </record>
    """
  end

  defp authors_dc(item) do
    authors = item.authors || []

    Enum.map_join(authors, "\n", fn a ->
      "<dc:creator>#{xml_escape(a)}</dc:creator>"
    end)
  end

  defp xml_escape(nil), do: ""

  defp xml_escape(s) do
    s
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  defp datestamp(nil), do: "1970-01-01T00:00:00Z"
  defp datestamp(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp datestamp(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_iso8601(ndt) <> "Z"

  defp error_response(code, message) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <OAI-PMH xmlns="http://www.openarchives.org/OAI/2.0/"
             xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
             xsi:schemaLocation="http://www.openarchives.org/OAI/2.0/ http://www.openarchives.org/OAI/2.0/OAI-PMH.xsd">
      <responseDate>#{now}</responseDate>
      <error code="#{code}">#{message}</error>
    </OAI-PMH>
    """
  end

  defp base_url do
    KirokuWeb.Endpoint.url()
  end
end
