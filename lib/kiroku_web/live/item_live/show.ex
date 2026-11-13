defmodule KirokuWeb.ItemLive.Show do
  use KirokuWeb, :live_view

  alias Kiroku.{Repository, Content, Analytics, Export}
  alias Kiroku.Access.Authorization

  import KirokuWeb.SEO, only: [item_meta: 1]

  alias KirokuWeb.SEO

  @impl true
  def mount(%{"handle" => handle}, _session, socket) do
    item =
      Repository.get_item_with_preloads(handle) ||
        raise Ecto.NoResultsError, queryable: Kiroku.Repository.Item

    current_user = socket.assigns[:current_user]

    if Authorization.can?(current_user, :read, item) do
      # Record the view only on the connected (websocket) mount — otherwise
      # the disconnected SSR render would double-count every visit.
      if connected?(socket) do
        Analytics.record_view(item.id, current_user, view_meta(socket))
      end

      ancestor_chain =
        if item.collection_id && item.collection do
          Repository.community_ancestor_chain(item.collection.community_id)
        else
          []
        end

      {:ok,
       socket
       |> SEO.put_page_seo(
         path: ~p"/items/#{item.handle}",
         description: SEO.page_description(item)
       )
       |> assign(:page_title, "#{item.title} — Kiroku")
       |> assign(:tombstone, nil)
       |> assign(:item, item)
       |> assign(:bitstreams, item.bitstreams)
       |> assign(:ancestor_chain, ancestor_chain)
       |> assign(:breadcrumb, breadcrumb_entries(ancestor_chain, item))
       |> assign(:view_count, Analytics.count_views(item.id))
       |> assign(:download_count, Analytics.count_downloads_for_item(item.id))
       |> assign(:citation_formats, ~w(apa mla chicago ieee bibtex ris))
       |> assign(:active_citation_tab, "apa")
       |> assign(:citations, generate_citations(item))
       |> assign(:reader, nil)}
    else
      # Non-public items (restricted, withdrawn, still in review) render a
      # tombstone notice — the handle stays stable but no metadata is exposed,
      # and `noindex, follow` keeps it out of search indexes.
      kind = tombstone_kind(item)

      {:ok,
       socket
       |> assign(:page_title, tombstone_page_title(kind))
       |> assign(:robots_meta, "noindex, follow")
       |> assign(:tombstone, kind)
       |> assign(:tombstone_handle, handle)
       |> assign(:reader, nil)
       |> assign(:contact_email, Kiroku.Settings.brand_settings().contact_email)}
    end
  end

  defp tombstone_kind(%{status: :withdrawn}), do: :withdrawn
  defp tombstone_kind(%{status: :embargoed}), do: :embargoed

  defp tombstone_kind(%{status: s}) when s in [:draft, :submitted, :under_review],
    do: :unpublished

  defp tombstone_kind(_), do: :restricted

  # Breadcrumb trail for the BreadcrumbList JSON-LD (root first):
  # Communities > ancestors… > collection > item.
  defp breadcrumb_entries(ancestor_chain, item) do
    root = [%{name: "Communities", url: SEO.canonical_url(~p"/communities")}]

    ancestors =
      Enum.map(ancestor_chain, fn community ->
        %{name: community.name, url: SEO.canonical_url(~p"/communities/#{community.handle}")}
      end)

    collection =
      if item.collection do
        [
          %{
            name: item.collection.name,
            url: SEO.canonical_url(~p"/collections/#{item.collection.handle}")
          }
        ]
      else
        []
      end

    root ++
      ancestors ++
      collection ++
      [%{name: item.title, url: SEO.canonical_url(~p"/items/#{item.handle}")}]
  end

  defp tombstone_page_title(:withdrawn), do: "Item withdrawn — Kiroku"
  defp tombstone_page_title(:embargoed), do: "Item under embargo — Kiroku"
  defp tombstone_page_title(:unpublished), do: "Item not yet published — Kiroku"
  defp tombstone_page_title(:restricted), do: "Item restricted — Kiroku"

  defp tombstone_heading(:withdrawn), do: "Item withdrawn"
  defp tombstone_heading(:embargoed), do: "Item under embargo"
  defp tombstone_heading(:unpublished), do: "Item not yet published"
  defp tombstone_heading(:restricted), do: "Item restricted"

  defp tombstone_message(:withdrawn) do
    "This item has been withdrawn from the repository and is no longer available."
  end

  defp tombstone_message(:embargoed) do
    "This item is temporarily unavailable while under embargo."
  end

  defp tombstone_message(:unpublished) do
    "This item has not been published yet — it may still be in review."
  end

  defp tombstone_message(:restricted) do
    "Access to this item is restricted and it cannot be shown publicly."
  end

  defp tombstone_detail(:withdrawn) do
    "If you believe this is a mistake, please contact the repository administrator."
  end

  defp tombstone_detail(:embargoed) do
    "Access will open automatically once the embargo period ends."
  end

  defp tombstone_detail(:unpublished) do
    "Please check back later, or search the repository for related works."
  end

  defp tombstone_detail(:restricted) do
    "If you believe you should have access, please contact the repository administrator."
  end

  @impl true
  def handle_event("select-citation-tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_citation_tab, tab)}
  end

  @impl true
  def handle_event("read_file", %{"id" => id}, socket) do
    user = socket.assigns.current_user
    item = socket.assigns.item
    bitstream = Enum.find(socket.assigns.bitstreams, &(&1.id == id))

    may_read =
      bitstream != nil and pdf_bitstream?(bitstream) and
        Authorization.can?(user, :read, item) and
        Content.accessible?(bitstream, user, item)

    if may_read do
      {:noreply,
       assign(socket, :reader, %{
         id: bitstream.id,
         label: bitstream.description || "Document"
       })}
    else
      {:noreply, put_flash(socket, :error, "This file cannot be opened in the reader.")}
    end
  end

  @impl true
  def handle_event("close_reader", _params, socket) do
    {:noreply, assign(socket, :reader, nil)}
  end

  # A file is reader-eligible when the mime says PDF *or* the filename ends in
  # .pdf — MSSQL-imported rows often have nil/generic mime types, and the
  # extension is a reliable fallback.
  defp pdf_bitstream?(%Content.Bitstream{mime_type: "application/pdf"}), do: true

  defp pdf_bitstream?(%Content.Bitstream{filename: filename}) when is_binary(filename),
    do: String.ends_with?(String.downcase(filename), ".pdf")

  defp pdf_bitstream?(_), do: false

  defp generate_citations(item) do
    preloads = %{authors: item.item_authors, keywords: item.item_keywords}

    ~w(apa mla chicago ieee bibtex ris)a
    |> Map.new(fn format ->
      text =
        case Export.Citation.generate(item, format, preloads) do
          {:ok, citation} -> citation
          {:error, _} -> ""
        end

      {Atom.to_string(format), text}
    end)
  end

  # Extracts the viewer's user-agent and (hashed) IP from the websocket
  # connect info, for analytics + bot filtering.
  defp view_meta(socket) do
    user_agent = Phoenix.LiveView.get_connect_info(socket, :user_agent)

    ip_hash =
      case Phoenix.LiveView.get_connect_info(socket, :peer_data) do
        %{address: address} -> Kiroku.Analytics.ip_hash(address)
        _ -> nil
      end

    [user_agent: user_agent, ip_hash: ip_hash]
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_user}>
      <%= if @tombstone do %>
        <%!-- Tombstone: non-public item — no metadata, noindex via root head --%>
        <div class="max-w-2xl mx-auto py-16 px-4" id="item-tombstone">
          <div class="kiroku-card-raised p-10 text-center">
            <div
              class="w-16 h-16 mx-auto rounded-full flex items-center justify-center mb-5"
              style="background: rgba(123,79,166,0.12);"
            >
              <.icon
                name="hero-lock-closed"
                class="w-8 h-8 text-[var(--color-patchouli)]"
              />
            </div>
            <h1
              class="font-heading text-2xl font-semibold mb-2"
              style="color: var(--color-lilac);"
            >
              {tombstone_heading(@tombstone)}
            </h1>
            <p class="text-sm leading-relaxed" style="color: var(--color-wisteria);">
              {tombstone_message(@tombstone)}
            </p>
            <p class="kiroku-handle text-sm mt-1 mb-5">{@tombstone_handle}</p>
            <p class="text-xs mb-6" style="color: var(--color-quill);">
              {tombstone_detail(@tombstone)}
            </p>
            <%= if @contact_email do %>
              <p class="text-xs mb-6" style="color: var(--color-quill);">
                Contact:
                <a
                  href={"mailto:#{@contact_email}"}
                  class="underline"
                  style="color: var(--color-patchouli);"
                >
                  {@contact_email}
                </a>
              </p>
            <% end %>
            <div class="flex flex-wrap gap-3 justify-center">
              <.link
                navigate={~p"/search"}
                class="flex items-center gap-2 text-sm px-4 py-2 rounded-lg font-medium transition-all duration-150 hover:scale-105"
                style="background: var(--color-patchouli); color: white;"
              >
                <.icon name="hero-magnifying-glass" class="w-4 h-4" /> Search items
              </.link>
              <.link
                navigate={~p"/communities"}
                class="flex items-center gap-2 text-sm px-4 py-2 rounded-lg font-medium transition-all duration-150 hover:scale-105"
                style="background: rgba(123,79,166,0.1); color: var(--color-wisteria); border: 1px solid rgba(123,79,166,0.2);"
              >
                <.icon name="hero-building-library" class="w-4 h-4" /> Browse communities
              </.link>
            </div>
          </div>
        </div>
      <% else %>
        <%!-- Structured-data + social meta tags for search engines & Scholar --%>
        <.item_meta item={@item} bitstreams={@bitstreams} breadcrumb={@breadcrumb} />
        <div class="max-w-5xl mx-auto space-y-6">
          <%!-- Breadcrumb (full hierarchy via recursive CTE) --%>
          <nav class="flex items-center gap-1.5 text-xs flex-wrap" style="color: var(--color-quill);">
            <.link
              navigate={~p"/communities"}
              class="hover:text-[var(--color-patchouli)] transition-colors"
            >
              Communities
            </.link>
            <%= if @item.collection do %>
              <%= for ancestor <- @ancestor_chain do %>
                <.icon name="hero-chevron-right" class="w-3 h-3 shrink-0 opacity-50" />
                <.link
                  navigate={~p"/communities/#{ancestor.handle}"}
                  class="hover:text-[var(--color-patchouli)] transition-colors"
                >
                  {ancestor.name}
                </.link>
              <% end %>
              <.icon name="hero-chevron-right" class="w-3 h-3 shrink-0 opacity-50" />
              <.link
                navigate={~p"/collections/#{@item.collection.handle}"}
                class="hover:text-[var(--color-patchouli)] transition-colors"
              >
                {@item.collection.name}
              </.link>
            <% end %>
          </nav>

          <%!-- Hero header card --%>
          <div class="kiroku-card-raised p-6 sm:p-8 space-y-5">
            <div class="flex gap-6">
              <%!-- Thumbnail (auto-generated or user-uploaded cover) --%>
              <%= if thumbnail = Enum.find(@bitstreams, &(&1.bundle_name == :THUMBNAIL)) do %>
                <div class="shrink-0 hidden sm:block">
                  <img
                    src={~p"/items/#{@item.handle}/bitstreams/#{thumbnail.id}"}
                    alt="Cover"
                    class="w-32 h-44 object-cover rounded-lg border"
                    style="border-color: rgba(155,126,200,0.15);"
                  />
                </div>
              <% end %>

              <div class="flex-1 min-w-0 space-y-5">
                <%!-- Type + Status badges --%>
                <div class="flex items-center gap-2 flex-wrap">
                  <span class="badge-item-type">{@item.item_type}</span>
                  <span class={["status-badge", to_string(@item.status)]}>{@item.status}</span>
                  <%= if @item.degree_level do %>
                    <span
                      class="text-xs px-2 py-0.5 rounded-full font-medium"
                      style="background: rgba(155,126,200,0.12); color: var(--color-wisteria);"
                    >
                      {String.upcase(to_string(@item.degree_level))}
                    </span>
                  <% end %>
                  <%= if @item.language do %>
                    <span
                      class="text-xs px-2 py-0.5 rounded-full font-medium"
                      style="background: rgba(155,126,200,0.08); color: var(--color-dust);"
                    >
                      {String.upcase(to_string(@item.language))}
                    </span>
                  <% end %>
                </div>

                <%!-- Title --%>
                <div class="space-y-2">
                  <h1
                    class="font-heading text-2xl sm:text-3xl font-semibold leading-tight"
                    style="color: var(--color-lilac);"
                  >
                    {@item.title}
                  </h1>
                  <%= if @item.title_alt do %>
                    <p class="font-body italic text-base" style="color: var(--color-quill);">
                      {@item.title_alt}
                    </p>
                  <% end %>
                </div>
              </div>
            </div>

            <%!-- Author + handle --%>
            <div class="flex items-center gap-4 flex-wrap">
              <%= if @item.student_name do %>
                <div class="flex items-center gap-2">
                  <div
                    class="w-9 h-9 rounded-full flex items-center justify-center shrink-0 text-sm font-bold"
                    style="background: rgba(123,79,166,0.2); color: var(--color-patchouli);"
                  >
                    {String.first(@item.student_name)}
                  </div>
                  <div>
                    <p class="text-sm font-medium" style="color: var(--color-wisteria);">
                      {@item.student_name}
                    </p>
                    <%= if @item.student_id do %>
                      <p class="text-xs" style="color: var(--color-quill);">
                        NPM: {@item.student_id}
                      </p>
                    <% end %>
                  </div>
                </div>
              <% end %>
            </div>

            <p class="kiroku-handle text-xs">{Kiroku.Settings.handle_prefix()}/{@item.handle}</p>

            <%!-- Metadata strip --%>
            <div
              class="grid grid-cols-2 sm:grid-cols-4 gap-3 pt-4 border-t"
              style="border-color: rgba(155,126,200,0.1);"
            >
              <%= if @item.faculty do %>
                <div>
                  <p
                    class="text-[10px] font-semibold uppercase tracking-wider mb-0.5"
                    style="color: var(--color-quill);"
                  >
                    Faculty
                  </p>
                  <p class="text-xs" style="color: var(--color-wisteria);">{@item.faculty}</p>
                </div>
              <% end %>
              <%= if @item.program_study do %>
                <div>
                  <p
                    class="text-[10px] font-semibold uppercase tracking-wider mb-0.5"
                    style="color: var(--color-quill);"
                  >
                    Program
                  </p>
                  <p class="text-xs" style="color: var(--color-wisteria);">{@item.program_study}</p>
                </div>
              <% end %>
              <%= if @item.date_submitted do %>
                <div>
                  <p
                    class="text-[10px] font-semibold uppercase tracking-wider mb-0.5"
                    style="color: var(--color-quill);"
                  >
                    Submitted
                  </p>
                  <p class="text-xs" style="color: var(--color-wisteria);">
                    {Calendar.strftime(@item.date_submitted, "%b %Y")}
                  </p>
                </div>
              <% end %>
              <%= if @item.institution do %>
                <div>
                  <p
                    class="text-[10px] font-semibold uppercase tracking-wider mb-0.5"
                    style="color: var(--color-quill);"
                  >
                    Institution
                  </p>
                  <p class="text-xs" style="color: var(--color-wisteria);">{@item.institution}</p>
                </div>
              <% end %>
            </div>
          </div>

          <%!-- Main content grid --%>
          <div class="grid lg:grid-cols-3 gap-6">
            <%!-- Left: Abstract + Keywords + Advisors --%>
            <div class="lg:col-span-2 space-y-6">
              <%= if @item.abstract do %>
                <div class="kiroku-card p-6">
                  <h2 class="font-heading text-lg mb-3" style="color: var(--color-lilac);">
                    Abstract
                  </h2>
                  <div
                    class="prose-content text-sm leading-relaxed whitespace-pre-line"
                    style="color: var(--color-wisteria);"
                  >
                    {@item.abstract}
                  </div>
                  <%= if @item.abstract_alt do %>
                    <div class="mt-4 pt-4 border-t" style="border-color: rgba(155,126,200,0.1);">
                      <p
                        class="text-[10px] uppercase tracking-wider mb-2 font-semibold"
                        style="color: var(--color-quill);"
                      >
                        English
                      </p>
                      <p
                        class="text-sm leading-relaxed italic whitespace-pre-line"
                        style="color: var(--color-quill);"
                      >
                        {@item.abstract_alt}
                      </p>
                    </div>
                  <% end %>
                </div>
              <% end %>

              <%= if @item.item_advisors != [] do %>
                <div class="kiroku-card p-6">
                  <h2 class="font-heading text-lg mb-3" style="color: var(--color-lilac);">
                    Advisors
                  </h2>
                  <div class="space-y-3">
                    <%= for advisor <- @item.item_advisors do %>
                      <div class="flex items-center gap-3">
                        <div
                          class="w-8 h-8 rounded-full flex items-center justify-center shrink-0 text-xs font-bold"
                          style="background: rgba(123,79,166,0.15); color: var(--color-patchouli);"
                        >
                          {String.first(advisor.advisor_name)}
                        </div>
                        <div>
                          <p class="text-sm font-medium" style="color: var(--color-wisteria);">
                            {advisor.advisor_name}
                          </p>
                          <%= if advisor.advisor_role do %>
                            <p class="text-xs" style="color: var(--color-quill);">
                              {advisor.advisor_role}
                            </p>
                          <% end %>
                        </div>
                      </div>
                    <% end %>
                  </div>
                </div>
              <% end %>

              <%= if @item.item_keywords != [] do %>
                <div class="kiroku-card p-6">
                  <h2 class="font-heading text-lg mb-3" style="color: var(--color-lilac);">
                    Keywords
                  </h2>
                  <div class="flex flex-wrap gap-2">
                    <%= for kw <- @item.item_keywords do %>
                      <.link
                        navigate={~p"/search?q=#{kw.keyword}"}
                        class="px-3 py-1 rounded-full text-xs font-medium transition-all hover:scale-105"
                        style="background: rgba(123,79,166,0.1); color: var(--color-wisteria); border: 1px solid rgba(123,79,166,0.2);"
                      >
                        {kw.keyword}
                      </.link>
                    <% end %>
                  </div>
                </div>
              <% end %>

              <%!-- Item Details --%>
              <div class="kiroku-card p-6">
                <h2 class="font-heading text-lg mb-3" style="color: var(--color-lilac);">
                  Item Details
                </h2>
                <dl class="space-y-2.5">
                  <%= if @item.doi do %>
                    <div class="flex justify-between gap-2 text-xs">
                      <dt style="color: var(--color-quill);" class="shrink-0">DOI</dt>
                      <a
                        href={"https://doi.org/#{@item.doi}"}
                        target="_blank"
                        rel="noopener"
                        class="font-mono hover:text-[var(--color-patchouli)] transition-colors text-right"
                        style="color: var(--color-ribbon-blue);"
                      >
                        {@item.doi}
                      </a>
                    </div>
                  <% end %>
                  <div class="flex justify-between gap-2 text-xs">
                    <dt style="color: var(--color-quill);" class="shrink-0">Type</dt>
                    <dd style="color: var(--color-wisteria);" class="text-right">
                      {@item.item_type}
                    </dd>
                  </div>
                  <div class="flex justify-between gap-2 text-xs">
                    <dt style="color: var(--color-quill);" class="shrink-0">Access</dt>
                    <dd style="color: var(--color-wisteria);" class="text-right">
                      {@item.access_level}
                    </dd>
                  </div>
                  <div class="flex justify-between gap-2 text-xs">
                    <dt style="color: var(--color-quill);" class="shrink-0">Views</dt>
                    <dd class="font-mono text-right" style="color: var(--color-wisteria);">
                      {@view_count}
                    </dd>
                  </div>
                  <div class="flex justify-between gap-2 text-xs">
                    <dt style="color: var(--color-quill);" class="shrink-0">Downloads</dt>
                    <dd class="font-mono text-right" style="color: var(--color-wisteria);">
                      {@download_count}
                    </dd>
                  </div>
                  <%= if @item.department do %>
                    <div class="flex justify-between gap-2 text-xs">
                      <dt style="color: var(--color-quill);" class="shrink-0">Dept. Code</dt>
                      <dd style="color: var(--color-wisteria);" class="text-right">
                        {@item.department}
                      </dd>
                    </div>
                  <% end %>
                </dl>
              </div>

              <%!-- Citation export with tabbed preview, copy & download --%>
              <div class="kiroku-card p-6">
                <h2 class="font-heading text-lg mb-4" style="color: var(--color-lilac);">
                  Export Citation
                </h2>

                <%!-- Format tabs --%>
                <div class="flex flex-wrap gap-1.5 mb-3" role="tablist">
                  <%= for format <- @citation_formats do %>
                    <button
                      type="button"
                      role="tab"
                      phx-click="select-citation-tab"
                      phx-value-tab={format}
                      aria-selected={to_string(@active_citation_tab == format)}
                      class={[
                        "px-3 py-1.5 rounded-lg text-xs font-medium transition-all duration-150",
                        if(@active_citation_tab == format,
                          do: "text-white shadow-sm",
                          else: "hover:scale-[1.03]"
                        )
                      ]}
                      style={
                        if(@active_citation_tab == format,
                          do:
                            "background: var(--color-patchouli); border: 1px solid var(--color-patchouli);",
                          else:
                            "background: rgba(123,79,166,0.08); color: var(--color-wisteria); border: 1px solid rgba(123,79,166,0.15);"
                        )
                      }
                    >
                      {String.upcase(format)}
                    </button>
                  <% end %>
                </div>

                <%!-- Citation preview --%>
                <div
                  class="relative rounded-lg overflow-hidden"
                  style="background: rgba(123,79,166,0.04); border: 1px solid rgba(123,79,166,0.12);"
                >
                  <pre
                    id="citation-preview"
                    phx-no-curly-interpolation
                    class="p-4 text-xs leading-relaxed whitespace-pre-wrap break-words font-mono overflow-x-auto max-h-48"
                    style="color: var(--color-wisteria);"
                  ><%= @citations[@active_citation_tab] %></pre>
                </div>

                <%!-- Actions: copy + download --%>
                <div class="flex items-center justify-end gap-2 mt-3">
                  <button
                    type="button"
                    id="copy-citation-btn"
                    phx-hook=".CopyCitation"
                    data-clipboard-text={@citations[@active_citation_tab]}
                    class="flex items-center gap-1.5 text-xs px-3 py-1.5 rounded-lg font-medium transition-all duration-150 hover:scale-105"
                    style="background: rgba(123,79,166,0.1); color: var(--color-wisteria); border: 1px solid rgba(123,79,166,0.2);"
                  >
                    <span data-copy-default class="inline-flex items-center gap-1.5">
                      <.icon name="hero-clipboard-document" class="w-3.5 h-3.5" /> Copy
                    </span>
                    <span
                      data-copy-success
                      class="hidden items-center gap-1.5"
                      style="color: var(--color-patchouli);"
                    >
                      <.icon name="hero-check-circle" class="w-3.5 h-3.5" /> Copied!
                    </span>
                  </button>

                  <a
                    href={"/citation/#{@item.id}/format/#{@active_citation_tab}"}
                    download
                    class="flex items-center gap-1.5 text-xs px-3 py-1.5 rounded-lg font-medium transition-all duration-150 hover:scale-105"
                    style="background: var(--color-patchouli); color: white; border: 1px solid var(--color-patchouli);"
                  >
                    <.icon name="hero-arrow-down-tray" class="w-3.5 h-3.5" /> Download
                  </a>
                </div>
              </div>
            </div>

            <%!-- Right sidebar: Files only --%>
            <div class="space-y-6">
              <%!-- Files --%>
              <% visible_bitstreams = Enum.reject(@bitstreams, &(&1.bundle_name == :THUMBNAIL)) %>
              <%= if @bitstreams != [] do %>
                <div class="kiroku-card p-5 sticky top-4">
                  <h2
                    class="font-heading text-lg mb-3 flex items-center gap-2"
                    style="color: var(--color-lilac);"
                  >
                    <.icon name="hero-folder-open" class="w-5 h-5" /> Files
                  </h2>
                  <%= if visible_bitstreams == [] do %>
                    <div class="text-center py-6">
                      <.icon name="hero-folder-open" class="w-8 h-8 mx-auto opacity-30" />
                      <p class="mt-2 text-sm" style="color: var(--color-quill);">
                        No files available for this item.
                      </p>
                    </div>
                  <% else %>
                    <div class="space-y-1.5">
                      <%= for bs <- visible_bitstreams do %>
                        <% can_access = Content.accessible?(bs, @current_user, @item) %>
                        <% locked = Content.bitstream_locked?(bs) %>
                        <%= if can_access do %>
                          <%= if pdf_bitstream?(bs) do %>
                            <%!-- PDFs open in the in-page reader — the direct
                            file URL is never rendered as a link, and the
                            original filename (often containing student
                            identifiers) is not displayed. --%>
                            <button
                              type="button"
                              phx-click="read_file"
                              phx-value-id={bs.id}
                              class="group w-full text-left flex items-center gap-2.5 p-2.5 rounded-lg transition-all hover:scale-[1.02] cursor-pointer"
                              style="background: rgba(123,79,166,0.06); border: 1px solid rgba(123,79,166,0.12);"
                            >
                              <.icon
                                name="hero-book-open"
                                class="w-4 h-4 shrink-0 text-[var(--color-patchouli)]"
                              />
                              <div class="min-w-0 flex-1">
                                <p
                                  class="text-xs font-medium truncate"
                                  style="color: var(--color-wisteria);"
                                >
                                  {bs.description || "Document"}
                                </p>
                              </div>
                              <.icon name="hero-book-open w-4 h-4 shrink-0 text-[var(--color-quill)] group-hover:text-[var(--color-patchouli)] transition-colors" />
                            </button>
                          <% else %>
                            <a
                              href={~p"/items/#{@item.handle}/bitstreams/#{bs.id}"}
                              target="_blank"
                              rel="noopener"
                              class="group flex items-center gap-2.5 p-2.5 rounded-lg transition-all hover:scale-[1.02]"
                              style="background: rgba(123,79,166,0.06); border: 1px solid rgba(123,79,166,0.12);"
                            >
                              <.icon
                                name="hero-document-text"
                                class="w-4 h-4 shrink-0 text-[var(--color-patchouli)]"
                              />
                              <div class="min-w-0 flex-1">
                                <p
                                  class="text-xs font-medium truncate"
                                  style="color: var(--color-wisteria);"
                                >
                                  {bs.description || "Document"}
                                </p>
                              </div>
                              <.icon name="hero-arrow-down-tray w-4 h-4 shrink-0 text-[var(--color-quill)] group-hover:text-[var(--color-patchouli)] transition-colors" />
                            </a>
                          <% end %>
                        <% else %>
                          <div
                            class="flex items-center gap-2.5 p-2.5 rounded-lg opacity-70"
                            style="background: rgba(155,126,200,0.03); border: 1px solid rgba(155,126,200,0.08);"
                            title={
                              cond do
                                locked and Kiroku.Settings.file_lock_mode() == :closed ->
                                  "Locked — restricted to superadmin"

                                locked ->
                                  "Locked — sign in with an internal account to view"

                                true ->
                                  "Restricted"
                              end
                            }
                          >
                            <.icon
                              name="hero-lock-closed"
                              class="w-4 h-4 shrink-0 text-[var(--color-quill)]"
                            />
                            <div class="min-w-0 flex-1">
                              <p
                                class="text-xs font-medium truncate"
                                style="color: var(--color-quill);"
                              >
                                {bs.description || "Document"}
                              </p>
                            </div>
                            <span
                              class="text-[10px] px-1.5 py-0.5 rounded font-medium shrink-0"
                              style="background: rgba(196,65,90,0.12); color: var(--color-ribbon-red);"
                            >
                              Locked
                            </span>
                          </div>
                        <% end %>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      <% end %>

      <%!-- PDF reader modal --%>
      <%= if @reader do %>
        <div
          class="fixed inset-0 z-50 flex items-center justify-center p-4"
          role="dialog"
          aria-modal="true"
          aria-label={@reader.label}
        >
          <div
            class="absolute inset-0 bg-black/70 backdrop-blur-sm"
            phx-click="close_reader"
            aria-hidden="true"
          >
          </div>

          <div class="relative w-full max-w-5xl h-[85vh] kiroku-card flex flex-col overflow-hidden">
            <div
              class="flex items-center gap-3 px-4 py-3 border-b shrink-0"
              style="border-color: rgba(123,79,166,0.15);"
            >
              <.icon
                name="hero-book-open"
                class="w-5 h-5 shrink-0"
                style="color: var(--color-patchouli);"
              />
              <p class="text-sm font-medium truncate flex-1" style="color: var(--color-lilac);">
                {@reader.label}
              </p>
              <button
                type="button"
                id="close-pdf-reader"
                phx-click="close_reader"
                class="p-1.5 rounded-lg transition-colors hover:opacity-80"
                style="color: var(--color-quill);"
                aria-label="Close reader"
              >
                <.icon name="hero-x-mark" class="w-5 h-5" />
              </button>
            </div>

            <div
              id="pdf-reader"
              phx-update="ignore"
              phx-hook="PdfReader"
              data-item-id={@item.id}
              data-bitstream-id={@reader.id}
              class="flex-1 min-h-0"
              style="background: var(--color-void);"
            >
            </div>
          </div>
        </div>
      <% end %>
    </Layouts.app>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".CopyCitation">
      export default {
        mounted() {
          this.el.addEventListener("click", () => {
            const text = this.el.dataset.clipboardText || "";
            const defaultEl = this.el.querySelector("[data-copy-default]");
            const successEl = this.el.querySelector("[data-copy-success]");

            const hide = (el) => {
              if (!el) return;
              el.classList.add("hidden");
              el.classList.remove("inline-flex");
            };
            const show = (el) => {
              if (!el) return;
              el.classList.remove("hidden");
              el.classList.add("inline-flex");
            };

            const showCopied = () => {
              hide(defaultEl);
              show(successEl);
              clearTimeout(this._copyTimer);
              this._copyTimer = setTimeout(() => {
                show(defaultEl);
                hide(successEl);
              }, 2000);
            };

            const fallback = () => {
              const ta = document.createElement("textarea");
              ta.value = text;
              ta.style.position = "fixed";
              ta.style.opacity = "0";
              document.body.appendChild(ta);
              ta.select();
              try {
                document.execCommand("copy");
              } catch (e) {}
              document.body.removeChild(ta);
              showCopied();
            };

            if (navigator.clipboard && navigator.clipboard.writeText) {
              navigator.clipboard.writeText(text).then(showCopied).catch(fallback);
            } else {
              fallback();
            }
          });
        },
        destroyed() {
          clearTimeout(this._copyTimer);
        }
      }
    </script>
    """
  end
end
