defmodule Kiroku.Sword.Builder do
  @moduledoc """
  Builds SWORD v2 XML responses (Service Document, Deposit Receipt, Statement).

  Uses raw string concatenation matching the OAI-PMH builder pattern — no XML
  library needed for emission. Inbound Atom entries are parsed with Erlang's
  built-in `:xmerl` (see `Kiroku.Sword.AtomParser`).
  """

  alias Kiroku.Repository.{Collection, Community, Item}

  @sword_version "2.0"
  @sword_max_upload_size 524_288_000

  # ── Service Document ─────────────────────────────────────────────────────────

  @doc """
  Builds the SWORD v2 Service Document as `application/atomserv+xml`.

  Lists all communities as SWORD workspaces and their collections as
  collection entries (the Col-IRIs that deposit clients POST to).
  """
  def service_document(workspaces) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <service xmlns="http://www.w3.org/2007/app" xmlns:atom="http://www.w3.org/2005/Atom" xmlns:sword="http://purl.org/net/sword/">
      <sword:version>#{@sword_version}</sword:version>
      <sword:maxUploadSize>#{@sword_max_upload_size}</sword:maxUploadSize>
    #{Enum.map_join(workspaces, "\n", &workspace_to_xml/1)}
    </service>
    """
  end

  defp workspace_to_xml(%Community{name: name, collections: collections}) do
    """
      <workspace>
        <atom:title>#{xml_escape(name)}</atom:title>
    #{Enum.map_join(collections || [], "\n", &collection_to_xml/1)}
      </workspace>
    """
  end

  defp collection_to_xml(%Collection{} = collection) do
    base = base_url()

    """
        <collection href="#{base}/sword-v2/collection/#{collection.handle}">
          <atom:title>#{xml_escape(collection.name)}</atom:title>
          <accept>application/atom+xml;type=entry</accept>
          <accept alternate="multipart-related"/>
          <sword:collectionPolicy>Deposit via SWORD v2</sword:collectionPolicy>
          <sword:treatment>Deposited items will be created as drafts pending review.</sword:treatment>
          <sword:mediation>false</sword:mediation>
        </collection>
    """
  end

  # ── Deposit Receipt ──────────────────────────────────────────────────────────

  @doc """
  Builds a SWORD v2 Deposit Receipt (`application/atom+xml`) returned after a
  successful deposit. Contains the item's handle, edit IRI, statement IRI, and
  SWORD state.
  """
  def deposit_receipt(%Item{} = item) do
    base = base_url()
    entry_id = "#{base}/sword-v2/statement/#{item.handle}"
    edit_iri = "#{base}/api/v1/items/#{item.id}"
    se_iri = "#{base}/sword-v2/statement/#{item.handle}"

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <entry xmlns="http://www.w3.org/2005/Atom" xmlns:sword="http://purl.org/net/sword/">
      <title>#{xml_escape(item.title || "Untitled")}</title>
      <id>#{entry_id}</id>
      <updated>#{DateTime.utc_now() |> DateTime.to_iso8601()}</updated>
      <link rel="self" href="#{entry_id}"/>
      <link rel="edit" href="#{edit_iri}"/>
      <link rel="http://purl.org/net/sword/terms/add" href="#{se_iri}"/>
      <sword:userAgent>Kiroku SWORD v2</sword:userAgent>
      <sword:treatment>Deposited. Item created as draft pending review.</sword:treatment>
      <sword:packaging>http://purl.org/net/sword/package/SimpleZip</sword:packaging>
      <sword:state href="#{se_iri}">
        <sword:version>#{@sword_version}</sword:version>
        <p>Draft — awaiting review</p>
      </sword:state>
    </entry>
    """
  end

  # ── Statement ─────────────────────────────────────────────────────────────────

  @doc """
  Builds a SWORD v2 Statement (`application/atom+xml`) describing the current
  state of a deposited item.
  """
  def statement(%Item{} = item) do
    base = base_url()
    state_description = state_description(item.status)
    se_iri = "#{base}/sword-v2/statement/#{item.handle}"

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom" xmlns:sword="http://purl.org/net/sword/">
      <id>#{se_iri}</id>
      <title>Statement for #{xml_escape(item.title || "Untitled")}</title>
      <updated>#{DateTime.utc_now() |> DateTime.to_iso8601()}</updated>
      <sword:state href="#{se_iri}">
        <sword:version>#{@sword_version}</sword:version>
        <p>#{state_description}</p>
      </sword:state>
      <entry>
        <title>#{xml_escape(item.title || "Untitled")}</title>
        <id>#{base}/api/v1/items/#{item.id}</id>
        <content type="application/json" src="#{base}/api/v1/items/#{item.id}"/>
        <link rel="edit" href="#{base}/api/v1/items/#{item.id}"/>
      </entry>
    </feed>
    """
  end

  # ── SWORD error document ────────────────────────────────────────────────────

  @doc """
  Builds a SWORD v2 error document for the given error variant and summary.
  """
  def error_doc(variant, summary) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <sword:error xmlns="http://www.w3.org/2005/Atom" xmlns:sword="http://purl.org/net/sword/">
      <title>#{xml_escape(variant)}</title>
      <updated>#{DateTime.utc_now() |> DateTime.to_iso8601()}</updated>
      <generator uri="https://kiroku.ai" version="1.0"/>
      <summary>#{xml_escape(summary)}</summary>
      <sword:verboseDescription>#{xml_escape(summary)}</sword:verboseDescription>
    </sword:error>
    """
  end

  defp state_description(:draft), do: "Draft — not yet submitted"
  defp state_description(:submitted), do: "Submitted — awaiting review"
  defp state_description(:under_review), do: "Under review"
  defp state_description(:published), do: "Published"
  defp state_description(:withdrawn), do: "Withdrawn"
  defp state_description(:embargoed), do: "Embargoed"
  defp state_description(_), do: "Unknown state"

  defp base_url, do: KirokuWeb.Endpoint.url()

  defp xml_escape(nil), do: ""

  defp xml_escape(string) when is_binary(string) do
    string
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end
end
