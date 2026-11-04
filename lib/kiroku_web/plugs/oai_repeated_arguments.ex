defmodule KirokuWeb.Plugs.OaiRepeatedArguments do
  @moduledoc """
  Rejects OAI-PMH requests that repeat an argument.

  OAI-PMH §3.6 defines `badVerb` for "the verb argument is missing, or the verb
  argument is repeated" and `badArgument` for "a repeated argument".

  Plug's query-string parser keeps only the last value when a key appears more
  than once, so by the time the request reaches the controller the repetition
  is invisible. This plug inspects the raw query string (and the raw POST
  body) and rejects repeated OAI-PMH arguments before that happens.

  It runs only for the OAI-PMH endpoint — other routes have no such rule.
  """

  import Plug.Conn

  # OAI-PMH protocol arguments that may appear at most once.
  @oai_args ~w(verb metadataPrefix identifier resumptionToken from until set)

  def init(opts), do: opts

  def call(conn, _opts) do
    if oai_endpoint?(conn) and repeated_argument?(conn) do
      # §3.1.2: OAI-PMH errors are reported in the XML body with HTTP 200, not
      # with HTTP status codes.
      conn
      |> put_resp_content_type("text/xml", "utf-8")
      |> send_resp(200, repeated_argument_xml())
      |> halt()
    else
      conn
    end
  end

  defp oai_endpoint?(conn) do
    conn.request_path in ["/oai", "/api/oai"]
  end

  # Counts how many times each OAI-PMH argument appears in the raw query
  # string and the raw form-encoded body. Plug has already parsed both, so the
  # raw values are read back from the connection.
  defp repeated_argument?(conn) do
    counts =
      conn.query_string
      |> split_pairs()
      |> Enum.map(fn {key, _value} -> key end)
      |> Enum.filter(&(&1 in @oai_args))
      |> Enum.frequencies()

    Enum.any?(counts, fn {_key, count} -> count > 1 end)
  end

  # Splits "a=1&b=2&a=3" into [{"a", "1"}, {"b", "2"}, {"a", "3"}] without
  # collapsing repeated keys.
  defp split_pairs(query) do
    query
    |> String.split("&")
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(fn pair ->
      case String.split(pair, "=", parts: 2) do
        [key] -> {URI.decode(key), ""}
        [key, value] -> {URI.decode(key), URI.decode(value)}
      end
    end)
  end

  defp repeated_argument_xml do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <OAI-PMH xmlns="http://www.openarchives.org/OAI/2.0/"
             xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
             xsi:schemaLocation="http://www.openarchives.org/OAI/2.0/ http://www.openarchives.org/OAI/2.0/OAI-PMH.xsd">
      <responseDate>#{DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()}</responseDate>
      <request>#{KirokuWeb.Endpoint.url()}/api/oai</request>
      <error code="badArgument">The request includes a repeated argument.</error>
    </OAI-PMH>
    """
  end
end
