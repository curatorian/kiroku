defmodule KirokuWeb.CommunityLive.Show do
  use KirokuWeb, :live_view

  alias Kiroku.Repository

  @impl true
  def mount(%{"handle" => handle}, _session, socket) do
    community = Repository.get_community_by_handle!(handle)
    collections = Repository.list_collections_for_community(community.id)

    {:ok,
     socket
     |> assign(:page_title, "#{community.name} — Kiroku")
     |> assign(:community, community)
     |> assign(:collections, collections)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_user}>
      <div class="space-y-8">
        <%!-- Breadcrumb --%>
        <nav class="flex items-center gap-2 text-sm" style="color: var(--color-quill);">
          <.link navigate={~p"/communities"} class="hover:text-white transition-colors">
            Communities
          </.link>
          <span>/</span>
          <span style="color: var(--color-wisteria);">{@community.name}</span>
        </nav>

        <%!-- Community header --%>
        <div class="kiroku-card-raised p-8">
          <div class="flex items-start gap-4">
            <div
              class="w-14 h-14 rounded-xl flex items-center justify-center shrink-0"
              style="background: rgba(123,79,166,0.25); color: var(--color-patchouli);"
            >
              <.icon name="hero-academic-cap" class="w-7 h-7" />
            </div>
            <div>
              <h1 class="font-heading text-3xl font-semibold" style="color: var(--color-lilac);">
                {@community.name}
              </h1>
              <p class="kiroku-handle mt-1">/{@community.handle}</p>
              <%= if @community.description do %>
                <p class="mt-3 leading-relaxed" style="color: var(--color-wisteria);">
                  {@community.description}
                </p>
              <% end %>
            </div>
          </div>
        </div>

        <%!-- Collections --%>
        <div>
          <h2 class="font-heading text-2xl mb-4" style="color: var(--color-lilac);">
            Collections
          </h2>
          <%= if @collections == [] do %>
            <div class="kiroku-card p-8 text-center">
              <p style="color: var(--color-quill);">No collections in this community yet.</p>
            </div>
          <% else %>
            <div class="grid gap-3 sm:grid-cols-2">
              <%= for collection <- @collections do %>
                <.link
                  navigate={~p"/collections/#{collection.handle}"}
                  class="kiroku-card p-4 flex items-center gap-3 hover:border-purple-500/40 transition-colors group"
                >
                  <div
                    class="w-9 h-9 rounded-lg flex items-center justify-center shrink-0"
                    style="background: rgba(196,168,224,0.1); color: var(--color-wisteria);"
                  >
                    <.icon name="hero-folder-open" class="w-4 h-4" />
                  </div>
                  <div class="min-w-0 flex-1">
                    <p
                      class="font-medium group-hover:text-white transition-colors"
                      style="color: var(--color-lilac);"
                    >
                      {collection.name}
                    </p>
                    <p class="kiroku-handle">{collection.handle}</p>
                    <%= if collection.short_description do %>
                      <p class="text-xs mt-0.5 line-clamp-1" style="color: var(--color-quill);">
                        {collection.short_description}
                      </p>
                    <% end %>
                  </div>
                  <.icon
                    name="hero-chevron-right"
                    class="w-4 h-4 shrink-0 text-[var(--color-quill)]"
                  />
                </.link>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
