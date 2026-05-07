defmodule Kiroku.Oai.Builder do
  @moduledoc """
  Builds OAI-PMH 2.0 XML responses.

  All public functions return an iodata/binary XML string. The controller is
  responsible for setting the Content-Type header and sending the response.

  Supported verbs: Identify, ListMetadataFormats, ListSets, ListIdentifiers,
  ListRecords, GetRecord.
  """

  alias Kiroku.{Repo, Repository}

  @repo_name Application.compile_env(:kiroku, :oai_repo_name, "Kiroku Institutional Repository")
  @repo_identifier Application.compile_env(:kiroku, :oai_repo_identifier, "oai:kiroku.ac.id")
  @admin_email Application.compile_env(:kiroku, :oai_admin_email, "admin@kiroku.ac.id")
  @metadata_formats [
    %{
      prefix: "oai_dc",
      schema: "http://www.openarchives.org/OAI/2.0/oai_dc.xsd",
      namespace: "http://www.openarchives.org/OAI/2.0/oai_dc/"
    }
  ]

  # ── Public verb handlers ─────────────────────────────────────────────────

  def identify do
    now = utc_now()

    wrap_envelope("Identify", now, ~s(<request verb="Identify">#{base_url()}/oai</request>), """
    <Identify>
      <repositoryName>#{@repo_name}</repositoryName>
      <baseURL>#{base_url()}/oai</baseURL>
      <protocolVersion>2.0</protocolVersion>
      <adminEmail>#{@admin_email}</adminEmail>
      <earliestDatestamp>2020-01-01T00:00:00Z</earliestDatestamp>
      <deletedRecord>no</deletedRecord>
      <granularity>YYYY-MM-DDThh:mm:ssZ</granularity>
    </Identify>
    """)
  end

  def list_metadata_formats do
    now = utc_now()

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

    wrap_envelope(
      "ListMetadataFormats",
      now,
      ~s(<request verb="ListMetadataFormats">#{base_url()}/oai</request>),
      "<ListMetadataFormats>#{formats}</ListMetadataFormats>"
    )
  end

  def list_sets do
    now = utc_now()
    communities = Repository.list_communities()

    sets =
      Enum.map_join(communities, "\n", fn c ->
        """
        <set>
          <setSpec>com_#{c.id}</setSpec>
          <setName>#{xml_escape(c.name)}</setName>
        </set>
        """
      end)

    wrap_envelope(
      "ListSets",
      now,
      ~s(<request verb="ListSets">#{base_url()}/oai</request>),
      "<ListSets>#{sets}</ListSets>"
    )
  end

  def list_identifiers(%{"metadataPrefix" => "oai_dc"} = params) do
    now = utc_now()
    items = Repository.list_published_items()

    headers =
      Enum.map_join(items, "\n", fn item ->
        """
        <header>
          <identifier>#{@repo_identifier}:#{item.id}</identifier>
          <datestamp>#{datestamp(item.published_at)}</datestamp>
        </header>
        """
      end)

    from_attr = if params["from"], do: ~s( from="#{params["from"]}"), else: ""
    until_attr = if params["until"], do: ~s( until="#{params["until"]}"), else: ""

    wrap_envelope(
      "ListIdentifiers",
      now,
      ~s(<request verb="ListIdentifiers" metadataPrefix="oai_dc"#{from_attr}#{until_attr}>#{base_url()}/oai</request>),
      "<ListIdentifiers>#{headers}</ListIdentifiers>"
    )
  end

  def list_identifiers(_params) do
    error("cannotDisseminateFormat", "Unsupported metadata format")
  end

  def list_records(%{"metadataPrefix" => "oai_dc"} = params) do
    now = utc_now()
    items = load_published_with_preloads()
    records = Enum.map_join(items, "\n", &item_to_oai_dc/1)

    from_attr = if params["from"], do: ~s( from="#{params["from"]}"), else: ""
    until_attr = if params["until"], do: ~s( until="#{params["until"]}"), else: ""

    wrap_envelope(
      "ListRecords",
      now,
      ~s(<request verb="ListRecords" metadataPrefix="oai_dc"#{from_attr}#{until_attr}>#{base_url()}/oai</request>),
      "<ListRecords>#{records}</ListRecords>"
    )
  end

  def list_records(_params) do
    error("cannotDisseminateFormat", "Unsupported metadata format")
  end

  def get_record(%{"metadataPrefix" => "oai_dc", "identifier" => identifier}) do
    now = utc_now()
    item_id = String.replace(identifier, "#{@repo_identifier}:", "")

    case Repo.get(Kiroku.Repository.Item, item_id) do
      nil ->
        error("idDoesNotExist", "Unknown identifier")

      item ->
        item = Repository.get_item_with_preloads!(item.id)

        wrap_envelope(
          "GetRecord",
          now,
          ~s(<request verb="GetRecord" identifier="#{identifier}" metadataPrefix="oai_dc">#{base_url()}/oai</request>),
          "<GetRecord>#{item_to_oai_dc(item)}</GetRecord>"
        )
    end
  end

  def get_record(_params) do
    error("badArgument", "Missing required arguments")
  end

  def error(code, message) do
    now = utc_now()

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

  # ── Private helpers ───────────────────────────────────────────────────────

  defp wrap_envelope(_verb, now, request_el, body) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <OAI-PMH xmlns="http://www.openarchives.org/OAI/2.0/"
             xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
             xsi:schemaLocation="http://www.openarchives.org/OAI/2.0/ http://www.openarchives.org/OAI/2.0/OAI-PMH.xsd">
      <responseDate>#{now}</responseDate>
      #{request_el}
      #{body}
    </OAI-PMH>
    """
  end

  defp item_to_oai_dc(item) do
    creators =
      (item.item_authors || [])
      |> Enum.map_join("\n", fn a ->
        "<dc:creator>#{xml_escape(a.author_name)}</dc:creator>"
      end)

    keywords =
      (item.item_keywords || [])
      |> Enum.map_join("\n", fn k ->
        "<dc:subject>#{xml_escape(k.keyword)}</dc:subject>"
      end)

    """
    <record>
      <header>
        <identifier>#{@repo_identifier}:#{item.id}</identifier>
        <datestamp>#{datestamp(item.published_at)}</datestamp>
      </header>
      <metadata>
        <oai_dc:dc xmlns:oai_dc="http://www.openarchives.org/OAI/2.0/oai_dc/"
                   xmlns:dc="http://purl.org/dc/elements/1.1/"
                   xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
                   xsi:schemaLocation="http://www.openarchives.org/OAI/2.0/oai_dc/ http://www.openarchives.org/OAI/2.0/oai_dc.xsd">
          <dc:title>#{xml_escape(item.title)}</dc:title>
          #{creators}
          #{keywords}
          <dc:date>#{datestamp(item.published_at)}</dc:date>
          #{if item.abstract, do: "<dc:description>#{xml_escape(item.abstract)}</dc:description>"}
          #{if item.doi, do: "<dc:identifier>#{xml_escape(item.doi)}</dc:identifier>"}
          <dc:identifier>#{base_url()}/items/#{item.handle || item.id}</dc:identifier>
          <dc:type>#{item.item_type}</dc:type>
          <dc:language>#{item.language || "id"}</dc:language>
          #{if item.publisher, do: "<dc:publisher>#{xml_escape(item.publisher)}</dc:publisher>"}
          #{if item.institution, do: "<dc:publisher>#{xml_escape(item.institution)}</dc:publisher>"}
          <dc:rights>#{rights_statement(item)}</dc:rights>
        </oai_dc:dc>
      </metadata>
    </record>
    """
  end

  defp rights_statement(%{access_level: :open}), do: "open"
  defp rights_statement(%{access_level: :restricted}), do: "restricted"
  defp rights_statement(_), do: "metadata only"

  defp load_published_with_preloads do
    Repository.list_published_items()
    |> Repo.preload([:item_authors, :item_keywords])
  end

  defp xml_escape(nil), do: ""

  defp xml_escape(s) when is_binary(s) do
    s
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  defp xml_escape(other), do: xml_escape(to_string(other))

  defp datestamp(nil), do: "1970-01-01T00:00:00Z"
  defp datestamp(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp datestamp(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_iso8601(ndt) <> "Z"
  defp datestamp(%Date{} = d), do: Date.to_iso8601(d) <> "T00:00:00Z"

  defp utc_now, do: DateTime.utc_now() |> DateTime.to_iso8601()

  defp base_url, do: KirokuWeb.Endpoint.url()
end
