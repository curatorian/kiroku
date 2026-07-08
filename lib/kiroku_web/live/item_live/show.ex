defmodule KirokuWeb.ItemLive.Show do
  use KirokuWeb, :live_view

  alias Kiroku.{Repository, Content, Analytics}
  alias Kiroku.Access.Authorization

  @impl true
  def mount(%{"handle" => handle}, _session, socket) do
    item = Repository.get_item_with_preloads!(handle)
    current_user = socket.assigns[:current_user]

    unless Authorization.can?(current_user, :read, item) do
      {:ok, push_navigate(socket, to: ~p"/")}
    else
      Analytics.record_view(item.id, current_user)

      ancestor_chain =
        if item.collection_id && item.collection do
          Repository.community_ancestor_chain(item.collection.community_id)
        else
          []
        end

      {:ok,
       socket
       |> assign(:page_title, "#{item.title} — Kiroku")
       |> assign(:item, item)
       |> assign(:bitstreams, item.bitstreams)
       |> assign(:ancestor_chain, ancestor_chain)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_user}>
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
                    <p class="text-xs" style="color: var(--color-quill);">NPM: {@item.student_id}</p>
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
                <h2 class="font-heading text-lg mb-3" style="color: var(--color-lilac);">Abstract</h2>
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
                <h2 class="font-heading text-lg mb-3" style="color: var(--color-lilac);">Advisors</h2>
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
                <h2 class="font-heading text-lg mb-3" style="color: var(--color-lilac);">Keywords</h2>
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
                  <dd style="color: var(--color-wisteria);" class="text-right">{@item.item_type}</dd>
                </div>
                <div class="flex justify-between gap-2 text-xs">
                  <dt style="color: var(--color-quill);" class="shrink-0">Access</dt>
                  <dd style="color: var(--color-wisteria);" class="text-right">
                    {@item.access_level}
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

            <%!-- Citation export --%>
            <div class="kiroku-card p-6">
              <h2 class="font-heading text-lg mb-3" style="color: var(--color-lilac);">
                Export Citation
              </h2>
              <div class="flex flex-wrap gap-2">
                <%= for format <- ~w(apa mla chicago ieee bibtex ris) do %>
                  <a
                    href={"/citation/#{@item.id}/format/#{format}"}
                    class="text-xs px-3 py-1.5 rounded-lg font-medium transition-all hover:scale-105"
                    style="background: rgba(123,79,166,0.1); color: var(--color-wisteria); border: 1px solid rgba(123,79,166,0.2);"
                  >
                    {String.upcase(format)}
                  </a>
                <% end %>
              </div>
            </div>
          </div>

          <%!-- Right sidebar: Files only --%>
          <div class="space-y-6">
            <%!-- Files --%>
            <%= if @bitstreams != [] do %>
              <div class="kiroku-card p-5 sticky top-4">
                <h2
                  class="font-heading text-lg mb-3 flex items-center gap-2"
                  style="color: var(--color-lilac);"
                >
                  <.icon name="hero-folder-open" class="w-5 h-5" /> Files
                </h2>
                <div class="space-y-1.5">
                  <%= for bs <- @bitstreams, bs.bundle_name != :THUMBNAIL do %>
                    <% can_access = Content.accessible?(bs, @current_user, @item) %>
                    <% locked = Content.bitstream_locked?(bs) %>
                    <%= if can_access do %>
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
                            {bs.description || bs.filename}
                          </p>
                          <p class="text-[10px] truncate" style="color: var(--color-quill);">
                            {bs.filename}
                          </p>
                        </div>
                        <.icon name="hero-arrow-down-tray w-4 h-4 shrink-0 text-[var(--color-quill)] group-hover:text-[var(--color-patchouli)] transition-colors" />
                      </a>
                    <% else %>
                      <div
                        class="flex items-center gap-2.5 p-2.5 rounded-lg opacity-70"
                        style="background: rgba(155,126,200,0.03); border: 1px solid rgba(155,126,200,0.08);"
                        title={
                          if locked,
                            do: "Locked — sign in with an internal account to view",
                            else: "Restricted"
                        }
                      >
                        <.icon
                          name="hero-lock-closed"
                          class="w-4 h-4 shrink-0 text-[var(--color-quill)]"
                        />
                        <div class="min-w-0 flex-1">
                          <p class="text-xs font-medium truncate" style="color: var(--color-quill);">
                            {bs.description || bs.filename}
                          </p>
                          <p class="text-[10px] truncate" style="color: var(--color-dust);">
                            {bs.filename}
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
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
