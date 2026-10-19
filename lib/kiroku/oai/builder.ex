defmodule Kiroku.Oai.Builder do
  @moduledoc """
  Builds OAI-PMH 2.0 XML responses.

  All public functions return a binary XML string. The controller is
  responsible for setting the Content-Type header and sending the response.

  Supported verbs: Identify, ListMetadataFormats, ListSets, ListIdentifiers,
  ListRecords, GetRecord.

  ListRecords / ListIdentifiers support `from`/`until` date selective
  harvesting, `set` scoping (`com_<id>` community / `col_<id>` collection), and
  `resumptionToken` pagination (stateless, base64-encoded cursor + parameters).

  Conformance notes (Open Archives Initiative, protocol v2.0 —
  https://www.openarchives.org/OAI/openarchivesprotocol.html):

    * every response validates against the official OAI-PMH.xsd — the root
      `OAI-PMH` element always carries `responseDate`, `request`, and third
      either one or more error elements or the verb container;
    * argument validation: illegal or missing arguments yield `badArgument`
      and unknown verbs yield `badVerb`; `resumptionToken` is an exclusive
      argument (§4.3/§4.5/§4.6);
    * `from`/`until` are syntax-validated, must share granularity (day or
      seconds), and `from <= until`; a day-granularity `until` is expanded to
      the end of that day so the bound is inclusive;
    * the `request` element echoes the received request arguments (bare base
      URL without attributes for `badVerb`/`badArgument`, per §3.2);
    * record headers include `setSpec` elements — required by §2.5/§2.6 when
      the repository advertises sets (which ListSets does);
    * the response that completes a paginated list includes an *empty*
      `resumptionToken` element (§3.5);
    * datestamps use the finest declared granularity — seconds, UTC `Z`.
  """

  alias Kiroku.{Repo, Repository}

  @page_size Application.compile_env(:kiroku, :oai_page_size, 100)
  @token_ttl_seconds 86_400

  @metadata_formats [
    %{
      prefix: "oai_dc",
      schema: "http://www.openarchives.org/OAI/2.0/oai_dc.xsd",
      namespace: "http://www.openarchives.org/OAI/2.0/oai_dc/"
    }
  ]

  @verbs [
    "Identify",
    "ListMetadataFormats",
    "ListSets",
    "GetRecord",
    "ListIdentifiers",
    "ListRecords"
  ]

  # Legal arguments per verb (§4). The `verb` argument itself is implicit and
  # not listed.
  @allowed_args %{
    "Identify" => [],
    "ListMetadataFormats" => ["identifier"],
    "ListSets" => ["resumptionToken"],
    "GetRecord" => ["identifier", "metadataPrefix"],
    "ListIdentifiers" => ["metadataPrefix", "from", "until", "set", "resumptionToken"],
    "ListRecords" => ["metadataPrefix", "from", "until", "set", "resumptionToken"]
  }

  @required_args %{
    "GetRecord" => ["identifier", "metadataPrefix"],
    "ListIdentifiers" => ["metadataPrefix"],
    "ListRecords" => ["metadataPrefix"]
  }

  # metadataPrefixType restricts the prefix to URI unreserved characters (§3.4).
  @metadata_prefix_regex ~r/\A[A-Za-z0-9\-_\.!~\*'\(\)]+\z/
  @day_regex ~r/\A\d{4}-\d{2}-\d{2}\z/
  @seconds_regex ~r/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/

  import Ecto.Query, only: [from: 2]

  # ── Public verb handlers ─────────────────────────────────────────────────

  def identify(params) do
    case validate_args("Identify", params) do
      :ok ->
        wrap_envelope("Identify", request_echo("Identify", params), """
        <Identify>
          <repositoryName>#{xml_escape(repo_name())}</repositoryName>
          <baseURL>#{xml_escape(base_url())}/oai</baseURL>
          <protocolVersion>2.0</protocolVersion>
          <adminEmail>#{xml_escape(admin_email())}</adminEmail>
          <earliestDatestamp>#{earliest_datestamp()}</earliestDatestamp>
          <deletedRecord>no</deletedRecord>
          <granularity>YYYY-MM-DDThh:mm:ssZ</granularity>
        </Identify>
        """)

      {:error, code, message} ->
        oai_error(code, message, params)
    end
  end

  def list_metadata_formats(params) do
    case validate_args("ListMetadataFormats", params) do
      :ok ->
        case do_list_metadata_formats(params) do
          {:formats, body} ->
            wrap_envelope(
              "ListMetadataFormats",
              request_echo("ListMetadataFormats", params),
              body
            )

          {:error, code, message} ->
            oai_error(code, message, params)
        end

      {:error, code, message} ->
        oai_error(code, message, params)
    end
  end

  defp do_list_metadata_formats(%{"identifier" => identifier}) do
    item_id = strip_oai_prefix(identifier)

    with {:ok, _} <- Ecto.UUID.cast(item_id),
         %Kiroku.Repository.Item{} <- Repo.get(Kiroku.Repository.Item, item_id) do
      {:formats, metadata_formats_xml()}
    else
      _ -> {:error, "idDoesNotExist", "Unknown identifier"}
    end
  end

  defp do_list_metadata_formats(_params), do: {:formats, metadata_formats_xml()}

  defp metadata_formats_xml do
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

    "<ListMetadataFormats>#{formats}</ListMetadataFormats>"
  end

  def list_sets(params) do
    case validate_args("ListSets", params) do
      :ok ->
        case do_list_sets(params) do
          {:sets, body} ->
            wrap_envelope("ListSets", request_echo("ListSets", params), body)

          {:error, code, message} ->
            oai_error(code, message, params)
        end

      {:error, code, message} ->
        oai_error(code, message, params)
    end
  end

  defp do_list_sets(%{"resumptionToken" => token}) do
    # ListSets is served complete in one response (no server-side pagination);
    # a structurally valid token is idempotently honoured as a no-op (§3.5.1).
    case decode_token(token) do
      {:ok, _state} ->
        set_listing()

      :error ->
        {:error, "badResumptionToken",
         "The value of the resumptionToken argument is invalid or expired."}
    end
  end

  defp do_list_sets(_params), do: set_listing()

  defp set_listing do
    %{communities: communities, collections: collections} = Repository.oai_sets()

    if communities == [] and collections == [] do
      {:error, "noSetHierarchy", "This repository does not support sets."}
    else
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

      {:sets, "<ListSets>#{Enum.join(comm_sets ++ coll_sets, "\n")}</ListSets>"}
    end
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

  def get_record(params) do
    case validate_args("GetRecord", params) do
      :ok -> do_get_record(params)
      {:error, code, message} -> oai_error(code, message, params)
    end
  end

  defp do_get_record(%{"metadataPrefix" => "oai_dc", "identifier" => identifier} = params) do
    item_id = strip_oai_prefix(identifier)

    # Repo.get on a non-UUID string raises; validate first so malformed
    # identifiers return idDoesNotExist instead of a 500. Only public,
    # published, discoverable items are served — consistent with ListRecords.
    with {:ok, _} <- Ecto.UUID.cast(item_id),
         item <- Repo.get(Kiroku.Repository.Item, item_id),
         %Kiroku.Repository.Item{} <- item,
         true <- oai_visible?(item) do
      item = Repository.get_item_with_preloads!(item.id)

      wrap_envelope(
        "GetRecord",
        request_echo("GetRecord", params),
        "<GetRecord>#{item_to_oai_dc(item)}</GetRecord>"
      )
    else
      _ -> oai_error("idDoesNotExist", "Unknown identifier", params)
    end
  end

  defp do_get_record(%{"metadataPrefix" => _unsupported} = params) do
    oai_error("cannotDisseminateFormat", "Unsupported metadata format", params)
  end

  defp do_get_record(params) do
    oai_error("badArgument", "Missing required arguments", params)
  end

  def error(code, message, params \\ %{}) do
    request_el =
      case code do
        c when c in ["badArgument", "badVerb"] ->
          # §3.2: badVerb / badArgument must return the base URL only — no
          # attributes on the request element.
          "<request>#{xml_escape(base_url())}/oai</request>"

        _ ->
          request_echo(Map.get(params, "verb"), params)
      end

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <OAI-PMH xmlns="http://www.openarchives.org/OAI/2.0/"
             xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
             xsi:schemaLocation="http://www.openarchives.org/OAI/2.0/ http://www.openarchives.org/OAI/2.0/OAI-PMH.xsd">
      <responseDate>#{utc_now()}</responseDate>
      #{request_el}
      <error code="#{code}">#{xml_escape(message)}</error>
    </OAI-PMH>
    """
  end

  defp oai_error(code, message, params), do: error(code, message, params)

  defp oai_visible?(item) do
    item.status == :published and item.discoverable == true and item.access_level == :open
  end

  # ── List pagination + filtering ──────────────────────────────────────────

  # Shared engine for ListRecords / ListIdentifiers: validates the request
  # (either a fresh harvest or a resumptionToken), queries a page, and renders
  # the container with the required resumptionToken state.
  defp render_list(verb, params, inner_fn) do
    case validate_list_args(verb, params) do
      :ok ->
        case oai_query(params) do
          {:ok, %{items: [], total: 0}} ->
            # Per OAI-PMH §3.2: a fresh request matching no records must error.
            oai_error("noRecordsMatch", "No records match the supplied criteria.", params)

          {:ok, %{items: items, total: total, offset: offset, next_token: next_token}} ->
            inner = inner_fn.(items)
            token = resumption_token_xml(next_token, total, offset, is_token_request?(params))
            body = "<#{verb}>#{inner}#{token}</#{verb}>"

            wrap_envelope(verb, request_echo(verb, params), body)

          {:error, code, message} ->
            oai_error(code, message, params)
        end

      {:error, code, message} ->
        oai_error(code, message, params)
    end
  end

  defp is_token_request?(%{"resumptionToken" => token}) when is_binary(token) and token != "",
    do: true

  defp is_token_request?(_), do: false

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
           next_token: next_token
         }}

      {:error, code, message} ->
        {:error, code, message}
    end
  end

  # A token request carries the original params in the token; per spec the
  # harvester sends only resumptionToken in that case (already enforced as an
  # exclusive argument). A fresh request must supply a valid metadataPrefix.
  defp parse_query(%{"resumptionToken" => token}) when is_binary(token) and token != "" do
    case decode_token(token) do
      {:ok, state} ->
        {:ok, state}

      :error ->
        {:error, "badResumptionToken",
         "The value of the resumptionToken argument is invalid or expired."}
    end
  end

  defp parse_query(%{"metadataPrefix" => "oai_dc"} = params) do
    with :ok <- validate_dates(params),
         :ok <- validate_set(params["set"]) do
      {:ok, from_dt, _from_granularity} = parse_date_bound(params["from"])
      {:ok, until_dt, until_granularity} = parse_date_bound(params["until"])

      {:ok,
       %{
         offset: 0,
         from: to_repo_date(from_dt),
         until: expand_day_until(until_dt, until_granularity),
         set: params["set"],
         prefix: "oai_dc",
         token: nil
       }}
    end
  end

  defp parse_query(%{"metadataPrefix" => _other}) do
    {:error, "cannotDisseminateFormat", "Unsupported metadata format"}
  end

  defp parse_query(_params) do
    {:error, "badArgument", "Missing required argument: metadataPrefix"}
  end

  # A setSpec that is syntactically fine but not advertised by ListSets
  # matches nothing → noRecordsMatch (was silently ignored before).
  defp validate_set(nil), do: :ok

  defp validate_set(set) do
    if known_set?(set) do
      :ok
    else
      {:error, "noRecordsMatch", "No records match the supplied criteria."}
    end
  end

  defp known_set?(set) do
    %{communities: comms, collections: cols} = Repository.oai_sets()

    Enum.any?(comms, &("com_#{&1.id}" == set)) or Enum.any?(cols, &("col_#{&1.id}" == set))
  end

  # ── Argument validation (§3.6 / §4) ──────────────────────────────────────

  defp validate_args(verb, verb_params, opts \\ []) do
    params = Map.delete(verb_params, "verb")
    allowed = @allowed_args[verb] || []
    required = @required_args[verb] || []
    check_required? = not Keyword.get(opts, :skip_required, false)

    extra = Enum.filter(Map.keys(params), &(not Enum.member?(allowed, &1)))
    missing = if check_required?, do: Enum.filter(required, &value_blank?(params[&1])), else: []

    cond do
      extra != [] ->
        {:error, "badArgument", "Illegal argument(s): #{Enum.join(extra, ", ")}"}

      missing != [] ->
        {:error, "badArgument", "Missing required argument(s): #{Enum.join(missing, ", ")}"}

      check_required? ->
        validate_metadata_prefix(verb, params)

      true ->
        :ok
    end
  end

  # Exclusive arguments: when `resumptionToken` is present it must be the only
  # argument besides `verb` (§4.3/§4.5/§4.6), and any other required argument
  # is carried inside the token instead.
  defp validate_list_args(verb, verb_params) do
    params = Map.delete(verb_params, "verb")
    token_present? = present?(params["resumptionToken"])
    other_args = Map.keys(Map.delete(params, "resumptionToken"))

    cond do
      token_present? and other_args != [] ->
        {:error, "badArgument", "resumptionToken must be the only argument"}

      token_present? ->
        validate_args(verb, verb_params, skip_required: true)

      true ->
        validate_args(verb, verb_params)
    end
  end

  defp validate_metadata_prefix(verb, params) do
    required = @required_args[verb] || []

    if "metadataPrefix" in required do
      case params["metadataPrefix"] do
        p when is_binary(p) ->
          if String.match?(p, @metadata_prefix_regex) do
            :ok
          else
            {:error, "badArgument", "Illegal metadataPrefix syntax"}
          end

        _ ->
          {:error, "badArgument", "Missing required argument(s): metadataPrefix"}
      end
    else
      :ok
    end
  end

  defp value_blank?(nil), do: true
  defp value_blank?(""), do: true
  defp value_blank?(_), do: false

  defp present?(value), do: not value_blank?(value)

  # ── Date validation (§3.3.1). `from`/`until` must be syntactically valid,
  # share the same granularity (day or seconds), and satisfy from <= until.
  defp validate_dates(params) do
    with {:ok, from_dt, from_g} <- parse_date_bound(params["from"]),
         {:ok, until_dt, until_g} <- parse_date_bound(params["until"]),
         :ok <- granularity_match?(from_g, until_g),
         :ok <- date_order_ok?(from_dt, until_dt) do
      :ok
    end
  end

  defp granularity_match?(nil, _from_g_or_nil_or_until), do: :ok
  defp granularity_match?(_from_nil, nil), do: :ok
  defp granularity_match?(g, g), do: :ok

  defp granularity_match?(_, _),
    do: {:error, "badArgument", "from and until must have the same granularity"}

  defp date_order_ok?(from_dt, until_dt)
       when from_dt != nil and until_dt != nil do
    if NaiveDateTime.compare(from_dt, until_dt) == :gt do
      {:error, "badArgument", "from must be less than or equal to until"}
    else
      :ok
    end
  end

  defp date_order_ok?(_, _), do: :ok

  # Returns {:ok, value, granularity} for a syntactically valid request date;
  # {:error, "badArgument", message} otherwise.
  defp parse_date_bound(nil), do: {:ok, nil, nil}

  defp parse_date_bound(str) when is_binary(str) do
    cond do
      String.match?(str, @day_regex) -> parse_day_bound(str)
      String.match?(str, @seconds_regex) -> parse_seconds_bound(str)
      true -> {:error, "badArgument", "Illegal date syntax: #{str}"}
    end
  end

  defp parse_date_bound(_), do: {:error, "badArgument", "Illegal date argument"}

  defp parse_day_bound(str) do
    case Date.from_iso8601(str) do
      {:ok, date} ->
        dt = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
        {:ok, dt, :day}

      {:error, _} ->
        {:error, "badArgument", "Illegal date: #{str}"}
    end
  end

  defp parse_seconds_bound(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> {:ok, dt, :seconds}
      {:error, _} -> {:error, "badArgument", "Illegal date: #{str}"}
    end
  end

  # A day-granularity `until` (inclusive, "less than or equal") must cover the
  # whole day when compared against a seconds-precision column.
  defp expand_day_until(nil, _), do: nil

  defp expand_day_until(dt, :day),
    do: DateTime.new!(DateTime.to_date(dt), ~T[23:59:59], "Etc/UTC")

  defp expand_day_until(dt, :seconds), do: dt

  # Repository operates on NaiveDateTime (items.updated_at column type).
  defp to_repo_date(nil), do: nil
  defp to_repo_date(%DateTime{} = dt), do: DateTime.to_naive(dt)

  # ── ResumptionToken rendering ─────────────────────────────────────────────

  # Fresh request that fits on a single page is a complete list (§3.5) — no
  # token. Fresh request with more data → non-empty token. Token request that
  # completes the list → EMPTY token element carrying cursor/completeListSize.
  defp resumption_token_xml(nil, total, offset, token_request?) do
    if token_request? do
      "<resumptionToken completeListSize=\"#{total}\" cursor=\"#{offset}\"/>"
    else
      ""
    end
  end

  defp resumption_token_xml(token, total, offset, _token_request?) do
    expiration =
      DateTime.utc_now()
      |> DateTime.add(@token_ttl_seconds, :second)
      |> DateTime.truncate(:second)
      |> DateTime.to_iso8601()

    "<resumptionToken completeListSize=\"#{total}\" cursor=\"#{offset}\" expirationDate=\"#{expiration}\">#{token}</resumptionToken>"
  end

  # ── Token encode/decode ───────────────────────────────────────────────────
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
         from: token_date(m["f"]),
         until: token_date(m["u"]),
         set: m["s"],
         prefix: m["p"] || "oai_dc",
         token: token
       }}
    else
      _ -> :error
    end
  end

  defp token_date(nil), do: nil

  defp token_date(str) do
    case NaiveDateTime.from_iso8601(str) do
      {:ok, ndt, _} -> ndt
      {:error, _} -> nil
    end
  end

  # ── Request element echo (§3.2) ───────────────────────────────────────────

  @request_arg_keys ["identifier", "metadataPrefix", "from", "until", "set", "resumptionToken"]

  # A nil verb is used for error responses that carry no legal verb argument.
  defp request_echo(nil, raw_params), do: wrap_request_attrs([], raw_params)

  defp request_echo(_verb, raw_params) do
    attrs =
      if raw_params["verb"] in @verbs do
        [~s(verb="#{xml_escape(raw_params["verb"])}")]
      else
        []
      end

    wrap_request_attrs(attrs, raw_params)
  end

  defp wrap_request_attrs(attrs, raw_params) do
    args =
      @request_arg_keys
      |> Enum.flat_map(fn key ->
        case raw_params[key] do
          v when is_binary(v) and v != "" -> [~s(#{key}="#{xml_escape(v)}")]
          _ -> []
        end
      end)

    case attrs ++ args do
      [] -> "<request>#{xml_escape(base_url())}/oai</request>"
      all -> "<request #{Enum.join(all, " ")}>#{xml_escape(base_url())}/oai</request>"
    end
  end

  # ── Record / header rendering ──────────────────────────────────────────────

  defp item_header_xml(item) do
    """
    <header>
      <identifier>#{xml_escape(oai_identifier(item))}</identifier>
      <datestamp>#{datestamp(item.updated_at)}</datestamp>
      #{setspecs_xml(item)}
    </header>
    """
  end

  defp item_to_oai_dc(item) do
    {primary, extras} =
      case ordered_authors(item) do
        [first | rest] -> {first, rest}
        [] -> {nil, []}
      end

    keywords =
      (item.item_keywords || []) |> Enum.map(&clean_value(&1.keyword)) |> Enum.reject(&is_nil/1)

    creators = if primary, do: "<dc:creator>#{xml_escape(primary)}</dc:creator>", else: ""

    contributors =
      extras
      |> Enum.map_join("\n", fn name ->
        "<dc:contributor>#{xml_escape(name)}</dc:contributor>"
      end)

    subjects =
      keywords
      |> Enum.map_join("\n", fn k ->
        "<dc:subject>#{xml_escape(k)}</dc:subject>"
      end)

    sources =
      [item.journal_name, item.conference_name]
      |> Enum.map(&clean_value/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.map_join("\n", fn source ->
        "<dc:source>#{xml_escape(source)}</dc:source>"
      end)

    publisher = clean_value(item.publisher)
    institution = clean_value(item.institution)
    doi = clean_value(item.doi)
    description = clean_value(item.abstract)
    date = dc_date(item)

    """
    <record>
      <header>
        <identifier>#{xml_escape(oai_identifier(item))}</identifier>
        <datestamp>#{datestamp(item.updated_at)}</datestamp>
        #{setspecs_xml(item)}
      </header>
      <metadata>
        <oai_dc:dc xmlns:oai_dc="http://www.openarchives.org/OAI/2.0/oai_dc/"
                   xmlns:dc="http://purl.org/dc/elements/1.1/"
                   xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
                   xsi:schemaLocation="http://www.openarchives.org/OAI/2.0/oai_dc/ http://www.openarchives.org/OAI/2.0/oai_dc.xsd">
          <dc:title>#{xml_escape(clean_value(item.title) || "")}</dc:title>
          #{creators}
          #{contributors}
          #{subjects}
          #{sources}
          #{if description, do: "<dc:description>#{xml_escape(description)}</dc:description>"}
          #{if doi, do: "<dc:identifier>#{xml_escape(doi)}</dc:identifier>"}
          <dc:identifier>#{xml_escape(base_url())}/items/#{item.handle || item.id}</dc:identifier>
          <dc:type>#{xml_escape(item.item_type)}</dc:type>
          <dc:language>#{xml_escape(item.language || "id")}</dc:language>
          #{if date != "", do: "<dc:date>#{date}</dc:date>", else: ""}
          #{if publisher, do: "<dc:publisher>#{xml_escape(publisher)}</dc:publisher>"}
          #{if institution, do: "<dc:publisher>#{xml_escape(institution)}</dc:publisher>"}
          <dc:rights>#{xml_escape(rights_statement(item))}</dc:rights>
        </oai_dc:dc>
      </metadata>
    </record>
    """
  end

  # Primary author (lowest sequence) becomes dc:creator; additional authors
  # become dc:contributor so consumer-facing records distinguish researcher
  # leadership from co-authors.
  defp ordered_authors(item) do
    (item.item_authors || [])
    |> Enum.sort_by(&{&1.sequence || 0, &1.id})
    |> Enum.map(&clean_value(&1.author_name))
    |> Enum.reject(&is_nil/1)
  end

  # Literal "NULL" strings leak from the legacy MSSQL data into record values;
  # never emit them (same convention as the migration importer). Blank strings
  # are normalized to nil so empty elements are omitted entirely.
  defp clean_value(nil), do: nil

  defp clean_value(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> if String.downcase(trimmed) == "null", do: nil, else: trimmed
    end
  end

  defp clean_value(other), do: clean_value(to_string(other))

  # §2.5/§2.6: when a repository advertises sets, record headers MUST include
  # the item's set memberships (ListIdentifiers / ListRecords / GetRecord).
  defp setspecs_xml(item) do
    case item.collection do
      %Kiroku.Repository.Collection{} = collection ->
        specs =
          ["col_#{collection.id}"] ++
            if collection.community_id, do: ["com_#{collection.community_id}"], else: []

        Enum.map_join(specs, "\n", fn spec -> "<setSpec>#{spec}</setSpec>" end)

      _ ->
        ""
    end
  end

  defp oai_identifier(item), do: "#{repo_identifier()}:#{item.id}"

  # Strips the configured OAI prefix ("oai:host:uuid" → "uuid").
  defp strip_oai_prefix(identifier) do
    prefix = repo_identifier() <> ":"

    case identifier do
      <<^prefix::binary, rest::binary>> -> rest
      _ -> identifier
    end
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

  defp utc_now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

  defp base_url, do: KirokuWeb.Endpoint.url()

  # Guaranteed lower bound of served datestamps (§4.2: "A repository must not
  # use datestamps lower than the one specified"). Rather than hardcode 2020 we
  # compute the actual earliest updated_at among served items and take the
  # earlier of the two; the default acts as a floor if the table is empty.
  defp earliest_datestamp do
    guaranteed = ~N[2020-01-01 00:00:00]

    actual =
      Repo.one(
        from(i in Kiroku.Repository.Item,
          where: i.status == :published and i.discoverable == true and i.access_level == :open,
          select: min(i.updated_at)
        )
      )

    earliest =
      case actual do
        %NaiveDateTime{} = ndt ->
          if NaiveDateTime.compare(ndt, guaranteed) == :lt, do: ndt, else: guaranteed

        _ ->
          guaranteed
      end

    NaiveDateTime.to_iso8601(earliest) <> "Z"
  end

  # Read at runtime so the identifier can be customized from the settings page
  # (DB setting → env var → compile-time config → default).
  defp repo_identifier, do: Kiroku.Settings.oai_repo_identifier()

  # Read at runtime so the repository name can be customized from the settings page.
  defp repo_name, do: Kiroku.Settings.oai_repo_name()

  # Read at runtime so the admin e-mail can be customized from the settings page.
  defp admin_email, do: Kiroku.Settings.oai_admin_email()
end
