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
      bitstreams = Content.list_bitstreams_for_item(item.id)

      {:ok,
       socket
       |> assign(:page_title, "#{item.title} — Kiroku")
       |> assign(:item, item)
       |> assign(:bitstreams, bitstreams)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_user}>
      <div class="max-w-4xl space-y-8">
        <%!-- Breadcrumb --%>
        <%= if @item.collection do %>
          <nav class="flex items-center gap-2 text-sm" style="color: var(--color-quill);">
            <.link navigate={~p"/communities"} class="hover:text-white transition-colors">
              Communities
            </.link>
            <span>/</span>
            <.link
              navigate={~p"/collections/#{@item.collection.handle}"}
              class="hover:text-white transition-colors"
            >
              {@item.collection.name}
            </.link>
            <span>/</span>
            <span class="truncate" style="color: var(--color-wisteria);">{@item.title}</span>
          </nav>
        <% end %>

        <%!-- Item header --%>
        <div class="kiroku-card-raised p-8 space-y-4">
          <%!-- Type + Status row --%>
          <div class="flex items-center gap-3 flex-wrap">
            <span class="badge-item-type">{@item.item_type}</span>
            <span class={["status-badge", to_string(@item.status)]}>{@item.status}</span>
            <%= if @item.language do %>
              <span
                class="text-xs px-2 py-0.5 rounded"
                style="background: rgba(155,126,200,0.08); color: var(--color-dust);"
              >
                {String.upcase(to_string(@item.language))}
              </span>
            <% end %>
          </div>

          <%!-- Title --%>
          <h1
            class="font-heading text-3xl font-semibold leading-tight"
            style="color: var(--color-lilac);"
          >
            {@item.title}
          </h1>
          <%= if @item.title_alt do %>
            <p class="font-body italic text-lg" style="color: var(--color-quill);">
              {@item.title_alt}
            </p>
          <% end %>

          <%!-- Handle --%>
          <p class="kiroku-handle">kiroku/{@item.handle}</p>

          <%!-- Key metadata grid --%>
          <div
            class="grid grid-cols-2 sm:grid-cols-3 gap-4 pt-2 border-t"
            style="border-color: rgba(155,126,200,0.1);"
          >
            <%= if @item.student_name do %>
              <div>
                <p
                  class="text-xs font-medium uppercase tracking-wider mb-0.5"
                  style="color: var(--color-quill);"
                >
                  Author
                </p>
                <p class="text-sm" style="color: var(--color-wisteria);">{@item.student_name}</p>
              </div>
            <% end %>
            <%= if @item.department do %>
              <div>
                <p
                  class="text-xs font-medium uppercase tracking-wider mb-0.5"
                  style="color: var(--color-quill);"
                >
                  Department
                </p>
                <p class="text-sm" style="color: var(--color-wisteria);">{@item.department}</p>
              </div>
            <% end %>
            <%= if @item.publication_year do %>
              <div>
                <p
                  class="text-xs font-medium uppercase tracking-wider mb-0.5"
                  style="color: var(--color-quill);"
                >
                  Year
                </p>
                <p class="text-sm" style="color: var(--color-wisteria);">
                  {@item.publication_year}
                </p>
              </div>
            <% end %>
            <%= if @item.degree_level do %>
              <div>
                <p
                  class="text-xs font-medium uppercase tracking-wider mb-0.5"
                  style="color: var(--color-quill);"
                >
                  Degree
                </p>
                <p class="text-sm" style="color: var(--color-wisteria);">
                  {String.upcase(to_string(@item.degree_level))}
                </p>
              </div>
            <% end %>
            <%= if @item.doi do %>
              <div>
                <p
                  class="text-xs font-medium uppercase tracking-wider mb-0.5"
                  style="color: var(--color-quill);"
                >
                  DOI
                </p>
                <a
                  href={"https://doi.org/#{@item.doi}"}
                  target="_blank"
                  rel="noopener"
                  class="font-mono text-xs hover:text-white transition-colors"
                  style="color: var(--color-ribbon-blue);"
                >
                  {@item.doi}
                </a>
              </div>
            <% end %>
          </div>

          <%!-- Citation download links --%>
          <div
            class="pt-3 border-t flex flex-wrap gap-2"
            style="border-color: rgba(155,126,200,0.1);"
          >
            <p class="text-xs w-full mb-1" style="color: var(--color-quill);">
              Export citation:
            </p>
            <%= for format <- ~w(apa mla chicago ieee bibtex ris) do %>
              <a
                href={"/citation/#{@item.id}/format/#{format}"}
                class="text-xs px-2.5 py-1 rounded-md transition-colors hover:border-purple-500/40"
                style="background: rgba(123,79,166,0.1); color: var(--color-wisteria); border: 1px solid rgba(123,79,166,0.2);"
              >
                {String.upcase(format)}
              </a>
            <% end %>
          </div>
        </div>

        <div class="grid lg:grid-cols-3 gap-6">
          <%!-- Main: abstract + keywords + advisors --%>
          <div class="lg:col-span-2 space-y-6">
            <%= if @item.abstract do %>
              <div class="kiroku-card p-6">
                <h2 class="font-heading text-xl mb-3" style="color: var(--color-lilac);">
                  Abstract
                </h2>
                <p
                  class="font-body text-sm leading-relaxed"
                  style="color: var(--color-wisteria);"
                >
                  {@item.abstract}
                </p>
                <%= if @item.abstract_alt do %>
                  <div
                    class="mt-4 pt-4 border-t"
                    style="border-color: rgba(155,126,200,0.1);"
                  >
                    <p
                      class="text-xs uppercase tracking-wider mb-2"
                      style="color: var(--color-quill);"
                    >
                      English
                    </p>
                    <p
                      class="font-body text-sm leading-relaxed italic"
                      style="color: var(--color-quill);"
                    >
                      {@item.abstract_alt}
                    </p>
                  </div>
                <% end %>
              </div>
            <% end %>

            <%!-- Keywords --%>
            <%= if @item.item_keywords != [] do %>
              <div class="kiroku-card p-6">
                <h2 class="font-heading text-xl mb-3" style="color: var(--color-lilac);">
                  Keywords
                </h2>
                <div class="flex flex-wrap gap-2">
                  <%= for kw <- @item.item_keywords do %>
                    <.link
                      navigate={~p"/search?q=#{kw.keyword}"}
                      class="px-3 py-1 rounded-full text-sm transition-colors hover:border-purple-400/60"
                      style="background: rgba(123,79,166,0.12); color: var(--color-wisteria); border: 1px solid rgba(123,79,166,0.25);"
                    >
                      {kw.keyword}
                    </.link>
                  <% end %>
                </div>
              </div>
            <% end %>

            <%!-- Advisors --%>
            <%= if @item.item_advisors != [] do %>
              <div class="kiroku-card p-6">
                <h2 class="font-heading text-xl mb-3" style="color: var(--color-lilac);">
                  Advisors
                </h2>
                <div class="space-y-2">
                  <%= for advisor <- @item.item_advisors do %>
                    <div class="flex items-center gap-3">
                      <div
                        class="w-8 h-8 rounded-full flex items-center justify-center shrink-0 text-xs font-bold"
                        style="background: rgba(123,79,166,0.2); color: var(--color-patchouli);"
                      >
                        {String.first(advisor.advisor_name)}
                      </div>
                      <div>
                        <p class="text-sm font-medium" style="color: var(--color-wisteria);">
                          {advisor.advisor_name}
                        </p>
                        <p class="text-xs" style="color: var(--color-quill);">
                          {advisor.advisor_role}
                        </p>
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>

          <%!-- Sidebar: files + metadata extras --%>
          <div class="space-y-4">
            <%!-- Files --%>
            <%= if @bitstreams != [] do %>
              <div class="kiroku-card p-5">
                <h2 class="font-heading text-lg mb-3" style="color: var(--color-lilac);">
                  Files
                </h2>
                <div class="space-y-2">
                  <%= for bs <- @bitstreams do %>
                    <%= if bs.bundle_name == :ORIGINAL do %>
                      <div
                        class="flex items-center gap-2 p-2 rounded-lg"
                        style="background: rgba(123,79,166,0.08);"
                      >
                        <.icon
                          name="hero-document-text"
                          class="w-4 h-4 shrink-0 text-[var(--color-patchouli)]"
                        />
                        <div class="min-w-0 flex-1">
                          <p class="text-xs truncate" style="color: var(--color-wisteria);">
                            {bs.filename}
                          </p>
                          <%= if bs.file_size do %>
                            <p class="text-xs" style="color: var(--color-quill);">
                              {Float.round(bs.file_size / 1_048_576, 1)} MB
                            </p>
                          <% end %>
                        </div>
                      </div>
                    <% end %>
                  <% end %>
                </div>
              </div>
            <% end %>

            <%!-- Metadata extras --%>
            <%= if @item.metadata_extras != [] do %>
              <div class="kiroku-card p-5">
                <h2 class="font-heading text-lg mb-3" style="color: var(--color-lilac);">
                  Details
                </h2>
                <dl class="space-y-2">
                  <%= for meta <- @item.metadata_extras do %>
                    <div>
                      <dt class="text-xs font-medium" style="color: var(--color-quill);">
                        {meta.field_schema}.{meta.field_element}
                        <%= if meta.field_qualifier do %>
                          .{meta.field_qualifier}
                        <% end %>
                      </dt>
                      <dd class="text-sm mt-0.5" style="color: var(--color-wisteria);">
                        {meta.field_value}
                      </dd>
                    </div>
                  <% end %>
                </dl>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
