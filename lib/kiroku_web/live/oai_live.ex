defmodule KirokuWeb.OaiLive do
  @moduledoc """
  Human-facing OAI-PMH page.

  This is the *UI* view of the OAI-PMH endpoint: it renders the same records
  the machine endpoint serves at `/api/oai`, but as a readable page instead of
  raw XML. The XML endpoint is the one harvesters talk to — this page exists
  so a human can explore the same data and discover the machine endpoint.

  Both views render from `Kiroku.Oai.Record`, so they can never drift apart.
  """

  use KirokuWeb, :live_view

  import KirokuWeb.KirokuComponents

  alias Kiroku.Oai.{Builder, Record}
  alias Kiroku.Repository

  @verbs ~w(Identify ListMetadataFormats ListSets ListIdentifiers ListRecords GetRecord)
  @page_size 25

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "OAI-PMH — Kiroku")
     |> assign(:verb, "Identify")
     |> assign(:records, [])
     |> assign(:identifiers, [])
     |> assign(:sets, [])
     |> assign(:formats, [])
     |> assign(:identify, nil)
     |> assign(:error, nil)
     |> assign(:identifier, "")
     |> assign(:record, nil)
     |> assign(:total, 0)
     |> assign(:offset, 0)
     |> assign(:next_offset, nil)
     |> assign(:selected_set, "")
     |> assign(:verbs, @verbs)
     |> assign(:api_endpoint, KirokuWeb.Endpoint.url() <> "/api/oai")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    # `oai_verb` (not `verb`) selects the displayed verb: `verb` is reserved for
    # the OAI-PMH protocol, and KirokuWeb.Plugs.OaiRedirect uses it to tell a
    # harvester request apart from UI browsing.
    verb = if params["oai_verb"] in @verbs, do: params["oai_verb"], else: "Identify"
    selected_set = params["set"] || ""

    socket =
      socket
      |> assign(:verb, verb)
      |> assign(:selected_set, selected_set)
      |> load_verb(verb, selected_set)
      |> assign(:api_verb_url, api_verb_url(verb, selected_set, socket.assigns.identifier))

    {:noreply, socket}
  end

  # The machine endpoint URL for the currently selected verb. The verb is
  # required — OAI-PMH answers `badVerb` for a request without one — so the
  # "Raw XML" link must always carry it.
  defp api_verb_url(verb, selected_set, identifier) do
    base = KirokuWeb.Endpoint.url() <> "/api/oai"

    query =
      case verb do
        "ListIdentifiers" -> "verb=#{verb}&metadataPrefix=oai_dc"
        "ListRecords" -> "verb=#{verb}&metadataPrefix=oai_dc"
        "GetRecord" -> "verb=#{verb}&metadataPrefix=oai_dc"
        _ -> "verb=#{verb}"
      end

    query =
      if selected_set != "" and verb in ["ListRecords", "ListIdentifiers"] do
        query <> "&set=#{URI.encode_www_form(selected_set)}"
      else
        query
      end

    query =
      if verb == "GetRecord" and identifier != "" do
        query <> "&identifier=#{URI.encode_www_form(identifier)}"
      else
        query
      end

    base <> "?" <> query
  end

  # ── Loading ────────────────────────────────────────────────────────────────

  defp load_verb(socket, "Identify", _set) do
    socket
    |> assign(:identify, identify_info())
    |> assign(:error, nil)
    |> assign(:records, [])
    |> assign(:identifiers, [])
  end

  defp load_verb(socket, "ListMetadataFormats", _set) do
    socket
    |> assign(:formats, metadata_formats())
    |> assign(:error, nil)
    |> assign(:records, [])
    |> assign(:identifiers, [])
  end

  defp load_verb(socket, "ListSets", _set) do
    socket
    |> assign(:sets, Repository.oai_sets())
    |> assign(:error, nil)
    |> assign(:records, [])
    |> assign(:identifiers, [])
  end

  defp load_verb(socket, "ListIdentifiers", set) do
    {items, total} = fetch_items(set)

    socket
    |> assign(:identifiers, Enum.map(items, &header_for/1))
    |> assign(:total, total)
    |> assign(:offset, 0)
    |> assign(:next_offset, next_offset(total, 0, length(items)))
    |> assign(:error, nil)
    |> assign(:records, [])
  end

  defp load_verb(socket, "ListRecords", set) do
    {items, total} = fetch_items(set)

    socket
    |> assign(:records, Record.for_items(items))
    |> assign(:total, total)
    |> assign(:offset, 0)
    |> assign(:next_offset, next_offset(total, 0, length(items)))
    |> assign(:error, nil)
    |> assign(:identifiers, [])
  end

  defp load_verb(socket, "GetRecord", _set) do
    socket
    |> assign(:records, [])
    |> assign(:identifiers, [])
    |> assign(:record, nil)
    |> assign(:error, nil)
  end

  defp fetch_items(set) do
    Repository.oai_items(set: set_param(set), offset: 0, limit: @page_size)
  end

  defp set_param(""), do: nil
  defp set_param(set), do: set

  defp next_offset(total, offset, returned) do
    if offset + returned < total, do: offset + returned, else: nil
  end

  defp header_for(item) do
    record = Record.for_item(item)
    %{identifier: record.identifier, datestamp: record.datestamp, set_specs: record.set_specs}
  end

  defp identify_info do
    %{
      repository_name: Kiroku.Settings.oai_repo_name(),
      base_url: KirokuWeb.Endpoint.url() <> "/api/oai",
      protocol_version: "2.0",
      admin_email: Kiroku.Settings.oai_admin_email(),
      granularity: "YYYY-MM-DDThh:mm:ssZ",
      earliest_datestamp: Builder.earliest_datestamp(),
      deleted_record: "no"
    }
  end

  defp metadata_formats do
    [
      %{
        prefix: "oai_dc",
        schema: "http://www.openarchives.org/OAI/2.0/oai_dc.xsd",
        namespace: "http://www.openarchives.org/OAI/2.0/oai_dc/"
      }
    ]
  end

  # ── Events ─────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("change_verb", %{"verb" => verb}, socket) do
    if verb in @verbs do
      {:noreply, push_patch(socket, to: ~p"/oai?#{[oai_verb: verb]}")}
    else
      {:noreply, socket}
    end
  end

  def handle_event("change_set", %{"set" => set}, socket) do
    params = [oai_verb: socket.assigns.verb]
    params = if set in [nil, ""], do: params, else: params ++ [set: set]

    {:noreply, push_patch(socket, to: ~p"/oai?#{params}")}
  end

  def handle_event("get_record", %{"identifier" => identifier}, socket) do
    identifier = String.trim(identifier)

    socket =
      socket
      |> assign(:identifier, identifier)
      |> assign(
        :api_verb_url,
        api_verb_url(socket.assigns.verb, socket.assigns.selected_set, identifier)
      )

    case fetch_oai_record(identifier) do
      {:ok, record} ->
        {:noreply, assign(socket, record: record, error: nil)}

      :error ->
        message =
          if identifier == "",
            do: "Enter a record identifier.",
            else: "No record matches that identifier."

        {:noreply, assign(socket, record: nil, error: message)}
    end
  end

  def handle_event("next_page", _params, socket) do
    case socket.assigns[:next_offset] do
      nil ->
        {:noreply, socket}

      offset ->
        {items, total} =
          Repository.oai_items(
            set: set_param(socket.assigns.selected_set),
            offset: offset,
            limit: @page_size
          )

        socket =
          socket
          |> assign(:records, Record.for_items(items))
          |> assign(:identifiers, Enum.map(items, &header_for/1))
          |> assign(:total, total)
          |> assign(:offset, offset)
          |> assign(:next_offset, next_offset(total, offset, length(items)))

        {:noreply, socket}
    end
  end

  # Resolves an OAI identifier ("oai:kiroku.ac.id:<uuid>") to a record. Only
  # publicly served items are returned — the same visibility rule the XML
  # endpoint applies to GetRecord.
  defp fetch_oai_record(identifier) do
    prefix = Kiroku.Settings.oai_repo_identifier() <> ":"

    item_id =
      case identifier do
        <<^prefix::binary, rest::binary>> -> rest
        _ -> identifier
      end

    with {:ok, _uuid} <- Ecto.UUID.cast(item_id),
         %Kiroku.Repository.Item{} = item <-
           Repository.get_item_with_preloads(item_id),
         true <-
           item.status == :published and item.discoverable == true and
             item.access_level == :open do
      {:ok, Record.for_item(item)}
    else
      _ -> :error
    end
  end

  # ── Render ─────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_user}>
      <div class="max-w-5xl">
        <.page_header
          title="OAI-PMH Endpoint"
          subtitle="Open Archives Initiative Protocol for Metadata Harvesting — version 2.0"
        >
          <:actions>
            <a
              href={@api_verb_url}
              target="_blank"
              rel="noopener"
              class="inline-flex items-center gap-1.5 text-xs px-3 py-1.5 rounded-lg transition-colors"
              style="border: 1px solid var(--color-dusk); color: var(--color-wisteria); background: var(--color-grimoire);"
            >
              <.icon name="hero-arrow-top-right-on-square" class="w-3.5 h-3.5" /> Raw XML
            </a>
          </:actions>
        </.page_header>

        <%!-- Endpoint notice: the UI here is a convenience; harvesters use /api/oai --%>
        <div
          id="oai-endpoint-notice"
          class="kiroku-card p-4 mb-6 flex flex-col sm:flex-row sm:items-center gap-3"
          style="border-left: 3px solid var(--color-patchouli); background: color-mix(in srgb, var(--color-patchouli) 8%, transparent);"
        >
          <.icon
            name="hero-information-circle"
            class="w-5 h-5 shrink-0"
            style="color: var(--color-patchouli);"
          />
          <div class="text-sm flex-1" style="color: var(--color-wisteria);">
            <span class="font-medium">Machine endpoint:</span>
            <code
              id="oai-api-endpoint"
              class="font-mono text-xs px-1.5 py-0.5 rounded"
              style="background: var(--color-dusk); color: var(--color-lilac);"
            >
              {@api_endpoint}
            </code>
            <span class="ml-1" style="color: var(--color-quill);">
              serves the OAI-PMH XML that harvesters consume. This page renders the same data for browsing.
            </span>
          </div>
        </div>

        <%!-- Verb selector --%>
        <div class="kiroku-card p-4 mb-6">
          <label
            for="oai-verb-select"
            class="block text-xs font-medium mb-2"
            style="color: var(--color-wisteria);"
          >
            Verb
          </label>
          <div class="flex flex-col sm:flex-row gap-3">
            <%!-- LiveView binds phx-change to the form, not to a bare input:
                 the form collects the named controls and sends them as params. --%>
            <form id="oai-verb-form" phx-change="change_verb" class="flex-1">
              <select
                id="oai-verb-select"
                name="verb"
                class="kiroku-search-input w-full"
              >
                <option :for={v <- @verbs} value={v} selected={v == @verb}>{v}</option>
              </select>
            </form>

            <%= if @verb in ["ListRecords", "ListIdentifiers"] do %>
              <form id="oai-set-form" phx-change="change_set" class="flex-1">
                <select
                  id="oai-set-select"
                  name="set"
                  class="kiroku-search-input w-full"
                >
                  <option value="" selected={@selected_set == ""}>All sets</option>
                  <option
                    :for={c <- community_sets(@sets)}
                    value={"com_#{c.id}"}
                    selected={@selected_set == "com_#{c.id}"}
                  >
                    {c.name}
                  </option>
                  <option
                    :for={c <- collection_sets(@sets)}
                    value={"col_#{c.id}"}
                    selected={@selected_set == "col_#{c.id}"}
                  >
                    {c.name}
                  </option>
                </select>
              </form>
            <% end %>
          </div>
        </div>

        <div id="oai-content" class="space-y-4">
          <%= if @verb == "Identify" do %>
            <.identify_panel info={@identify} />
          <% else %>
            <%= if @verb == "ListMetadataFormats" do %>
              <.formats_panel formats={@formats} />
            <% else %>
              <%= if @verb == "ListSets" do %>
                <.sets_panel sets={@sets} />
              <% else %>
                <%= if @verb == "ListIdentifiers" do %>
                  <.identifiers_panel identifiers={@identifiers} total={@total} />
                <% else %>
                  <%= if @verb == "GetRecord" do %>
                    <.get_record_panel identifier={@identifier} record={@record} error={@error} />
                  <% else %>
                    <.records_panel records={@records} total={@total} />
                  <% end %>
                <% end %>
              <% end %>
            <% end %>
          <% end %>

          <%= if @next_offset do %>
            <div class="flex justify-center pt-2">
              <button
                id="oai-next-page"
                phx-click="next_page"
                class="inline-flex items-center gap-1.5 text-sm px-4 py-2 rounded-lg font-medium transition-all hover:opacity-90"
                style="background: var(--color-patchouli); color: white;"
              >
                Next page <.icon name="hero-arrow-right" class="w-4 h-4" />
              </button>
            </div>
          <% end %>
        </div>

        <%!-- Raw XML of the current request --%>
        <div class="mt-8">
          <details id="oai-raw-details" class="kiroku-card overflow-hidden">
            <summary
              class="cursor-pointer select-none px-4 py-3 text-sm font-medium flex items-center gap-2"
              style="color: var(--color-wisteria);"
            >
              <.icon name="hero-code-bracket" class="w-4 h-4" /> View the XML this page renders
            </summary>
            <div class="px-4 pb-4">
              <p class="text-xs mb-2" style="color: var(--color-quill);">
                Exactly what <code class="font-mono break-all">{@api_verb_url}</code>
                returns for these parameters:
              </p>
              <pre
                id="oai-raw-xml"
                class="font-mono text-xs p-3 rounded-lg overflow-x-auto max-h-96"
                style="background: var(--color-dusk); color: var(--color-lilac);"
              >{raw_xml(@verb, @selected_set, @identifier)}</pre>
            </div>
          </details>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # ── Panels ─────────────────────────────────────────────────────────────────

  attr :info, :map, required: true

  defp identify_panel(assigns) do
    ~H"""
    <div id="oai-identify" class="kiroku-card p-5">
      <h2 class="font-heading text-lg mb-4" style="color: var(--color-lilac);">
        Repository Information
      </h2>
      <dl class="grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-3">
        <.info_row label="Repository Name" value={@info.repository_name} />
        <.info_row label="Base URL" value={@info.base_url} mono />
        <.info_row label="Protocol Version" value={@info.protocol_version} />
        <.info_row label="Admin Email" value={@info.admin_email} />
        <.info_row label="Earliest Datestamp" value={@info.earliest_datestamp} mono />
        <.info_row label="Granularity" value={@info.granularity} mono />
        <.info_row label="Deleted Record" value={@info.deleted_record} />
      </dl>
    </div>
    """
  end

  attr :formats, :list, required: true

  defp formats_panel(assigns) do
    ~H"""
    <div id="oai-formats" class="space-y-3">
      <h2 class="font-heading text-lg" style="color: var(--color-lilac);">
        Available Metadata Formats
      </h2>
      <div :for={f <- @formats} class="kiroku-card p-4">
        <div class="font-mono text-sm font-medium mb-2" style="color: var(--color-patchouli);">
          {f.prefix}
        </div>
        <dl class="grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-2">
          <.info_row label="Schema" value={f.schema} mono />
          <.info_row label="Namespace" value={f.namespace} mono />
        </dl>
      </div>
    </div>
    """
  end

  attr :sets, :map, required: true

  defp sets_panel(assigns) do
    ~H"""
    <div id="oai-sets" class="space-y-4">
      <div>
        <h2 class="font-heading text-lg" style="color: var(--color-lilac);">Communities</h2>
        <div :if={@sets.communities == []} class="text-sm mt-2" style="color: var(--color-quill);">
          No communities defined.
        </div>
        <div class="mt-2 grid grid-cols-1 sm:grid-cols-2 gap-2">
          <div :for={c <- @sets.communities} class="kiroku-card p-3">
            <div class="text-sm font-medium" style="color: var(--color-lilac);">{c.name}</div>
            <div class="font-mono text-xs mt-1" style="color: var(--color-quill);">com_{c.id}</div>
          </div>
        </div>
      </div>

      <div>
        <h2 class="font-heading text-lg" style="color: var(--color-lilac);">Collections</h2>
        <div :if={@sets.collections == []} class="text-sm mt-2" style="color: var(--color-quill);">
          No collections defined.
        </div>
        <div class="mt-2 grid grid-cols-1 sm:grid-cols-2 gap-2">
          <div :for={c <- @sets.collections} class="kiroku-card p-3">
            <div class="text-sm font-medium" style="color: var(--color-lilac);">{c.name}</div>
            <div class="font-mono text-xs mt-1" style="color: var(--color-quill);">col_{c.id}</div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :identifiers, :list, required: true
  attr :total, :integer, required: true

  defp identifiers_panel(assigns) do
    ~H"""
    <div id="oai-identifiers" class="space-y-2">
      <div class="flex items-baseline justify-between">
        <h2 class="font-heading text-lg" style="color: var(--color-lilac);">Record Identifiers</h2>
        <span id="oai-identifier-count" class="text-xs" style="color: var(--color-quill);">
          showing {length(@identifiers)} of {@total}
        </span>
      </div>
      <div :for={h <- @identifiers} class="kiroku-card p-3">
        <div class="font-mono text-xs break-all" style="color: var(--color-lilac);">
          {h.identifier}
        </div>
        <div
          class="flex flex-wrap items-center gap-3 mt-1.5 text-xs"
          style="color: var(--color-quill);"
        >
          <span class="font-mono">{h.datestamp}</span>
          <span :for={spec <- h.set_specs} class="font-mono" style="color: var(--color-lavender);">
            {spec}
          </span>
        </div>
      </div>
    </div>
    """
  end

  attr :identifier, :string, default: ""
  attr :record, :map, default: nil
  attr :error, :string, default: nil

  defp get_record_panel(assigns) do
    ~H"""
    <div id="oai-get-record" class="space-y-4">
      <div class="kiroku-card p-4">
        <form id="oai-get-record-form" phx-submit="get_record">
          <label
            for="oai-identifier-input"
            class="block text-xs font-medium mb-2"
            style="color: var(--color-wisteria);"
          >
            Record identifier
          </label>
          <div class="flex flex-col sm:flex-row gap-2">
            <input
              type="text"
              id="oai-identifier-input"
              name="identifier"
              value={@identifier}
              placeholder="oai:kiroku.ac.id:00000000-0000-0000-0000-000000000000"
              class="kiroku-search-input flex-1 font-mono text-sm"
            />
            <button
              type="submit"
              id="oai-get-record-submit"
              class="px-4 py-2 rounded-lg text-sm font-medium transition-all hover:opacity-90 shrink-0"
              style="background: var(--color-patchouli); color: white;"
            >
              Fetch record
            </button>
          </div>
          <p class="text-xs mt-2" style="color: var(--color-quill);">
            Copy an identifier from the ListIdentifiers or ListRecords view and paste it here.
          </p>
        </form>
      </div>

      <div
        :if={@error}
        id="oai-get-record-error"
        class="kiroku-card p-4 text-sm"
        style="border-color: var(--color-ribbon-red); color: var(--color-ribbon-red);"
      >
        {@error}
      </div>

      <article :if={@record} class="kiroku-card p-4" id="oai-get-record-result">
        <h3 class="font-heading text-base mb-1" style="color: var(--color-lilac);">
          {@record.title}
        </h3>
        <div class="font-mono text-xs mb-3 break-all" style="color: var(--color-quill);">
          {@record.identifier}
        </div>

        <dl class="grid grid-cols-1 sm:grid-cols-[7rem_1fr] gap-x-4 gap-y-1.5 text-sm">
          <.dc_row label="creator" values={@record.creators} />
          <.dc_row label="contributor" values={@record.contributors} />
          <.dc_row label="subject" values={@record.subjects} />
          <.dc_row label="source" values={@record.sources} />
          <.dc_row label="publisher" values={@record.publishers} />
          <.dc_row label="date" values={@record.dates} />
          <.dc_row label="type" values={@record.types} />
          <.dc_row label="language" values={@record.languages} />
          <.dc_row label="rights" values={[@record.rights]} />
          <.dc_row label="identifier" values={@record.identifiers} mono />
        </dl>

        <div
          :for={d <- @record.descriptions}
          class="mt-3 pt-3 text-sm"
          style="border-top: 1px solid var(--color-dusk); color: var(--color-wisteria);"
        >
          {d}
        </div>
      </article>
    </div>
    """
  end

  attr :records, :list, required: true
  attr :total, :integer, required: true

  defp records_panel(assigns) do
    ~H"""
    <div id="oai-records" class="space-y-3">
      <div class="flex items-baseline justify-between">
        <h2 class="font-heading text-lg" style="color: var(--color-lilac);">Records</h2>
        <span id="oai-record-count" class="text-xs" style="color: var(--color-quill);">
          showing {length(@records)} of {@total}
        </span>
      </div>

      <div
        :if={@records == []}
        class="kiroku-card p-8 text-center text-sm"
        style="color: var(--color-quill);"
      >
        No records match the current criteria.
      </div>

      <article :for={r <- @records} class="kiroku-card p-4" id={"oai-record-#{r.identifier}"}>
        <h3 class="font-heading text-base mb-1" style="color: var(--color-lilac);">{r.title}</h3>
        <div class="font-mono text-xs mb-3 break-all" style="color: var(--color-quill);">
          {r.identifier}
        </div>

        <dl class="grid grid-cols-1 sm:grid-cols-[7rem_1fr] gap-x-4 gap-y-1.5 text-sm">
          <.dc_row label="creator" values={r.creators} />
          <.dc_row label="contributor" values={r.contributors} />
          <.dc_row label="subject" values={r.subjects} />
          <.dc_row label="source" values={r.sources} />
          <.dc_row label="publisher" values={r.publishers} />
          <.dc_row label="date" values={r.dates} />
          <.dc_row label="type" values={r.types} />
          <.dc_row label="language" values={r.languages} />
          <.dc_row label="rights" values={[r.rights]} />
          <.dc_row label="identifier" values={r.identifiers} mono />
        </dl>

        <div
          :for={d <- r.descriptions}
          class="mt-3 pt-3 text-sm"
          style="border-top: 1px solid var(--color-dusk); color: var(--color-wisteria);"
        >
          {d}
        </div>

        <div :if={r.set_specs != []} class="flex flex-wrap gap-2 mt-3">
          <span
            :for={spec <- r.set_specs}
            class="text-xs font-mono px-2 py-0.5 rounded"
            style="background: color-mix(in srgb, var(--color-patchouli) 15%, transparent); color: var(--color-lavender);"
          >
            {spec}
          </span>
        </div>
      </article>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :mono, :boolean, default: false

  defp info_row(assigns) do
    ~H"""
    <div class="flex flex-col sm:flex-row sm:gap-3">
      <dt class="text-xs shrink-0 sm:w-36" style="color: var(--color-quill);">{@label}</dt>
      <dd class={["text-sm break-all", @mono && "font-mono"]} style="color: var(--color-lilac);">
        {@value}
      </dd>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :values, :list, required: true
  attr :mono, :boolean, default: false

  defp dc_row(assigns) do
    ~H"""
    <div :if={@values != []} class="contents">
      <dt class="text-xs font-mono shrink-0 sm:w-36" style="color: var(--color-quill);">
        dc:{@label}
      </dt>
      <dd class={["text-sm", @mono && "font-mono"]} style="color: var(--color-wisteria);">
        <div :for={v <- @values}>{v}</div>
      </dd>
    </div>
    """
  end

  # ── Helpers ────────────────────────────────────────────────────────────────

  defp community_sets(%{communities: communities}), do: communities
  defp community_sets(_), do: []

  defp collection_sets(%{collections: collections}), do: collections
  defp collection_sets(_), do: []

  # The XML the machine endpoint returns for the currently selected verb — shown
  # verbatim so the UI and the harvestable output can be compared directly.
  defp raw_xml(verb, selected_set, identifier) do
    params =
      case verb do
        "Identify" -> %{"verb" => verb}
        "ListMetadataFormats" -> %{"verb" => verb}
        "ListSets" -> %{"verb" => verb}
        "ListIdentifiers" -> %{"verb" => verb, "metadataPrefix" => "oai_dc"}
        "ListRecords" -> %{"verb" => verb, "metadataPrefix" => "oai_dc"}
        "GetRecord" -> %{"verb" => verb, "metadataPrefix" => "oai_dc"}
      end

    params =
      if selected_set != "" and verb in ["ListIdentifiers", "ListRecords"] do
        Map.put(params, "set", selected_set)
      else
        params
      end

    params =
      if verb == "GetRecord" and identifier != "" do
        Map.put(params, "identifier", identifier)
      else
        params
      end

    # The preview shows exactly what the machine endpoint returns, so it must
    # declare the same endpoint in its <request> element (§3.2).
    Builder.put_endpoint("/api/oai")
    Builder.raw_xml(params)
  end
end
