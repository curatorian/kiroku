defmodule Kiroku.Oai.Builder do
  @moduledoc """
  Builds OAI-PMH 2.0 XML responses.

  All public functions return an iodata/binary XML string. The controller is
  responsible for setting the Content-Type header and sending the response.

  Supported verbs: Identify, ListMetadataFormats, ListSets, ListIdentifiers,
  ListRecords, GetRecord.

  ListRecords / ListIdentifiers support `from`/`until` date selective
  harvesting, `set` scoping (`com_<id>` community / `col_<id>` collection), and
  `resumptionToken` pagination (stateless, base64-encoded cursor + parameters).
  """

  alias Kiroku.{Repo, Repository}

  @repo_name Application.compile_env(:kiroku, :oai_repo_name, "Kiroku Institutional Repository")
  @repo_identifier Application.compile_env(:kiroku, :oai_repo_identifier, "oai:kiroku.ac.id")
  @admin_email Application.compile_env(:kiroku, :oai_admin_email, "admin@kiroku.ac.id")
  @page_size Application.compile_env(:kiroku, :oai_page_size, 100)
  @token_ttl_seconds 86_400

  @metadata_formats [
    %{
      prefix: "oai_dc",
      schema: "http://www.openarchives.org/OAI/2.0/oai_dc.xsd",
      namespace: "http://www.openarchives.org/OAI/2.0/oai_dc/"
    }
  ]

  # ── Public verb handlers ─────────────────────────────────────────────────

  def identify do
    wrap_envelope("Identify", ~s(<request verb="Identify">#{base_url()}/oai</request>), """
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
      ~s(<request verb="ListMetadataFormats">#{base_url()}/oai</request>),
      "<ListMetadataFormats>#{formats}</ListMetadataFormats>"
    )
  end

  def list_sets do
    %{communities: communities, collections: collections} = Repository.oai_sets()

    comm_sets =
      Enum.map(communities, fn c ->
        """
        <set>
          <setSpec>com_#{c.id}</setSpec>
          <setName>#{xml_escape(c.name)}</setName>
        </set>
        """
      end)

    coll_sets =
      Enum.map(collections, fn c ->
        """
        <set>
          <setSpec>col_#{c.id}</setSpec>
          <setName>#{xml_escape(c.name)}</setName>
        </set>
        """
      end)

    wrap_envelope(
      "ListSets",
      ~s(<request verb="ListSets">#{base_url()}/oai</request>),
      "<ListSets>#{Enum.join(comm_sets ++ coll_sets, "\n")}</ListSets>"
    )
  end

  def list_identifiers(params) do
    render_list("ListIdentifiers", params, fn items ->
      Enum.map_join(items, "\n", &item_header_xml/1)
    end)
  end

  def list_records(params) do
    render_list("ListRecords", params, fn items ->
      Enum.map_join(items, "\n", &item_to_oai_dc/1)
    end)
  end

  def get_record(%{"metadataPrefix" => "oai_dc", "identifier" => identifier}) do
    item_id = String.replace(identifier, "#{@repo_identifier}:", "")

    # Repo.get on a non-UUID string raises; validate first so malformed
    # identifiers return idDoesNotExist instead of a 500.
    with {:ok, _} <- Ecto.UUID.cast(item_id),
         %Kiroku.Repository.Item{} = item <- Repo.get(Kiroku.Repository.Item, item_id) do
      item = Repository.get_item_with_preloads!(item.id)

      wrap_envelope(
        "GetRecord",
        ~s(<request verb="GetRecord" identifier="#{xml_escape(identifier)}" metadataPrefix="oai_dc">#{base_url()}/oai</request>),
        "<GetRecord>#{item_to_oai_dc(item)}</GetRecord>"
      )
    else
      _ -> error("idDoesNotExist", "Unknown identifier")
    end
  end

  def get_record(_params) do
    error("badArgument", "Missing required arguments")
  end

  def error(code, message) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <OAI-PMH xmlns="http://www.openarchives.org/OAI/2.0/"
             xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
             xsi:schemaLocation="http://www.openarchives.org/OAI/2.0/ http://www.openarchives.org/OAI/2.0/OAI-PMH.xsd">
      <responseDate>#{utc_now()}</responseDate>
      <error code="#{code}">#{message}</error>
    </OAI-PMH>
    """
  end

  # ── List pagination + filtering ──────────────────────────────────────────

  # Shared engine for ListRecords / ListIdentifiers: parses the request (either
  # a fresh harvest or a resumptionToken), queries a page, and renders the
  # container with an optional resumptionToken.
  defp render_list(verb, params, inner_fn) do
    case oai_query(params) do
      {:ok, %{items: [], total: 0, offset: 0}} ->
        # Per OAI-PMH §3.2: a fresh request matching no records must error.
        error("noRecordsMatch", "No records match the supplied criteria.")

      {:ok, %{items: items, total: total, offset: offset, next_token: next_token, state: state}} ->
        inner = inner_fn.(items)
        token = resumption_token_xml(next_token, total, offset)
        body = "<#{verb}>#{inner}#{token}</#{verb}>"

        wrap_envelope(verb, request_element(verb, state), body)

      {:error, code, message} ->
        error(code, message)
    end
  end

  defp oai_query(params) do
    case parse_query(params) do
      {:ok, state} ->
        {items, total} =
          Repository.oai_items(
            from: state.from,
            until: state.until,
            set: state.set,
            offset: state.offset,
            limit: @page_size
          )

        returned = length(items)
        next_offset = state.offset + returned

        next_token =
          if next_offset < total do
            encode_token(next_offset, state)
          else
            nil
          end

        {:ok,
         %{
           items: items,
           total: total,
           offset: state.offset,
           next_token: next_token,
           state: state
         }}

      {:error, _, _} = err ->
        err
    end
  end

  # A token request carries the original params in the token; per spec the
  # harvester sends only resumptionToken in that case. A fresh request must
  # supply a valid metadataPrefix.
  defp parse_query(%{"resumptionToken" => token}) when is_binary(token) and token != "" do
    case decode_token(token) do
      {:ok, state} ->
        {:ok, %{state | token: token}}

      :error ->
        {:error, "badResumptionToken",
         "The value of the resumptionToken argument is invalid or expired."}
    end
  end

  defp parse_query(%{"metadataPrefix" => "oai_dc"} = params) do
    {:ok,
     %{
       offset: 0,
       from: parse_date(params["from"]),
       until: parse_date(params["until"]),
       set: params["set"],
       prefix: "oai_dc",
       token: nil
     }}
  end

  defp parse_query(%{"metadataPrefix" => _other}) do
    {:error, "cannotDisseminateFormat", "Unsupported metadata format"}
  end

  defp parse_query(_params) do
    {:error, "badArgument", "Missing required argument: metadataPrefix"}
  end

  defp resumption_token_xml(nil, _total, _offset), do: ""

  defp resumption_token_xml(token, total, offset) do
    expiration =
      DateTime.utc_now()
      |> DateTime.add(@token_ttl_seconds, :second)
      |> DateTime.to_iso8601()

    "<resumptionToken completeListSize=\"#{total}\" cursor=\"#{offset}\" expirationDate=\"#{expiration}\">#{token}</resumptionToken>"
  end

  # ── Token encode/decode ────────────────────────────────────────────────────
  #
  # Stateless, opaque base64 of a tiny JSON map. OAI tokens are not a security
  # mechanism — they only carry the cursor position and original filters so the
  # harvester need not resend them. Not cryptographically signed.

  defp encode_token(offset, state) do
    %{
      "o" => offset,
      "f" => state.from && NaiveDateTime.to_iso8601(state.from),
      "u" => state.until && NaiveDateTime.to_iso8601(state.until),
      "s" => state.set,
      "p" => state.prefix
    }
    |> Jason.encode!()
    |> Base.url_encode64()
  end

  defp decode_token(token) do
    with {:ok, json} <- Base.url_decode64(token),
         {:ok, %{"o" => offset} = m} <- Jason.decode(json) do
      {:ok,
       %{
         offset: offset,
         from: parse_date(m["f"]),
         until: parse_date(m["u"]),
         set: m["s"],
         prefix: m["p"],
         token: nil
       }}
    else
      _ -> :error
    end
  end

  # ── Request element + date parsing ─────────────────────────────────────────

  defp request_element(verb, %{token: token}) when is_binary(token) and token != "" do
    ~s(<request verb="#{verb}" resumptionToken="#{xml_escape(token)}">#{base_url()}/oai</request>)
  end

  defp request_element(verb, state) do
    attrs =
      [~s(metadataPrefix="#{state.prefix}")]
      |> add_attr("from", state.from && oai_date(state.from))
      |> add_attr("until", state.until && oai_date(state.until))
      |> add_attr("set", state.set)

    ~s(<request verb="#{verb}" #{Enum.join(attrs, " ")}>#{base_url()}/oai</request>)
  end

  defp add_attr(list, _key, nil), do: list
  defp add_attr(list, key, value), do: list ++ [~s(#{key}="#{value}")]

  # Accepts both date-only ("2024-01-01") and full ("2024-01-01T00:00:00Z")
  # strings as harvesters send both. Returns a UTC NaiveDateTime to match the
  # items.updated_at column type.
  defp parse_date(nil), do: nil

  defp parse_date(str) when is_binary(str) do
    normalized = if String.contains?(str, "T"), do: str, else: str <> "T00:00:00Z"

    case DateTime.from_iso8601(normalized) do
      {:ok, dt, _} -> DateTime.to_naive(dt)
      {:error, _} -> nil
    end
  end

  defp oai_date(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_iso8601(ndt) <> "Z"

  # ── Record / header rendering ──────────────────────────────────────────────

  defp item_header_xml(item) do
    """
    <header>
      <identifier>#{@repo_identifier}:#{item.id}</identifier>
      <datestamp>#{datestamp(item.updated_at)}</datestamp>
    </header>
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
        <datestamp>#{datestamp(item.updated_at)}</datestamp>
      </header>
      <metadata>
        <oai_dc:dc xmlns:oai_dc="http://www.openarchives.org/OAI/2.0/oai_dc/"
                   xmlns:dc="http://purl.org/dc/elements/1.1/"
                   xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
                   xsi:schemaLocation="http://www.openarchives.org/OAI/2.0/oai_dc/ http://www.openarchives.org/OAI/2.0/oai_dc.xsd">
          <dc:title>#{xml_escape(item.title)}</dc:title>
          #{creators}
          #{keywords}
          <dc:date>#{dc_date(item)}</dc:date>
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

  defp dc_date(%{date_issued: %Date{} = d}), do: Date.to_iso8601(d)
  defp dc_date(%{publication_year: y}) when is_integer(y), do: to_string(y)
  defp dc_date(%{updated_at: %NaiveDateTime{} = ndt}), do: NaiveDateTime.to_iso8601(ndt) <> "Z"
  defp dc_date(_), do: ""

  defp rights_statement(%{access_level: :open}), do: "open"
  defp rights_statement(%{access_level: :internal}), do: "internal"
  defp rights_statement(%{access_level: :restricted}), do: "restricted"
  defp rights_statement(_), do: "metadata only"

  # ── XML helpers ────────────────────────────────────────────────────────────

  defp wrap_envelope(_verb, request_el, body) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <OAI-PMH xmlns="http://www.openarchives.org/OAI/2.0/"
             xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
             xsi:schemaLocation="http://www.openarchives.org/OAI/2.0/ http://www.openarchives.org/OAI/2.0/OAI-PMH.xsd">
      <responseDate>#{utc_now()}</responseDate>
      #{request_el}
      #{body}
    </OAI-PMH>
    """
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
