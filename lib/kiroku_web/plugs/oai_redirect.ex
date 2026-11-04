defmodule KirokuWeb.Plugs.OaiRedirect do
  @moduledoc """
  Redirects legacy OAI-PMH requests from `/oai` to the machine endpoint.

  OAI-PMH harvesters are configured with a single base URL. Historically that
  URL was `/oai`; the XML now lives at `/api/oai` while `/oai` renders the
  human-facing page. Rather than break existing harvester configurations, any
  request carrying OAI-PMH protocol arguments is redirected to `/api/oai` with
  the same arguments.

  This runs as a plug (not a competing route) because the `/oai` LiveView route
  matches every GET request — a controller route placed after it would be
  unreachable.

  ## Distinguishing protocol requests from UI browsing

  The UI page selects the verb to display with the `oai_verb` parameter, so
  `verb` remains reserved for the OAI-PMH protocol. A request is treated as a
  protocol request when it carries any of the OAI-PMH arguments — `verb`,
  `metadataPrefix`, `identifier`, `resumptionToken`, `from`, `until`, `set` —
  and none of them is the UI's own `oai_verb`.

  ## HTTP methods

  §3.1.1 requires repositories to support both GET and POST. A GET carries its
  arguments in the query string and is redirected with 302. A POST carries them
  in a form-encoded body; that body is replayed on the redirect, so the
  redirect uses 307 (See Other) to preserve both the method and the body.
  """

  import Plug.Conn

  # OAI-PMH protocol arguments. `verb` is the discriminator — without it there
  # is nothing to harvest.
  @oai_args ~w(verb metadataPrefix identifier resumptionToken from until set)

  def init(opts), do: opts

  def call(conn, _opts) do
    params = request_params(conn)

    if oai_request?(params) do
      redirect_to_api(conn, params)
    else
      conn
    end
  end

  # The OAI-PMH arguments, whether they arrived in the query string (GET) or
  # in a form-encoded body (POST).
  defp request_params(conn) do
    case conn.body_params do
      %Plug.Conn.Unfetched{} -> conn.query_params
      body_params -> Map.merge(conn.query_params, body_params)
    end
  end

  defp redirect_to_api(conn, params) do
    if conn.method == "POST" do
      # 307 preserves the method and replays the body. The arguments are
      # rewritten into the query string because the body may carry unrelated
      # fields, and the endpoint reads its arguments from either source.
      conn
      |> put_resp_content_type("text/xml", "utf-8")
      |> send_resp(
        307,
        [
          "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
          "<html><head><title>Moved</title></head><body>",
          "Moved to <a href=\"/api/oai?#{query_string(params)}\">/api/oai</a>.",
          "</body></html>"
        ]
        |> Enum.join("\n")
      )
      |> halt()
    else
      conn
      |> Phoenix.Controller.redirect(to: "/api/oai?" <> query_string(params))
      |> halt()
    end
  end

  defp oai_request?(params) do
    # The UI page never sets these protocol arguments — it uses `oai_verb` and
    # `set` for browsing. `set` is shared with the protocol, so it only counts
    # as a protocol signal when paired with another protocol argument.
    protocol_only = Map.take(params, @oai_args -- ["set"])

    cond do
      Map.has_key?(params, "oai_verb") ->
        false

      Enum.any?(protocol_only, fn {key, value} ->
        key in @oai_args and value not in [nil, ""]
      end) ->
        true

      Map.has_key?(params, "set") and params["set"] not in [nil, ""] ->
        true

      true ->
        false
    end
  end

  # Rebuilds the query string from the known OAI arguments so unrelated
  # parameters (e.g. LiveView tracking ids) are not carried over. The argument
  # order follows @oai_args so the generated URL is deterministic.
  defp query_string(params) do
    @oai_args
    |> Enum.map(fn key -> {key, params[key]} end)
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> URI.encode_query()
  end
end
