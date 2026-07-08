defmodule KirokuWeb.BrowseLive do
  use KirokuWeb, :live_view

  alias Kiroku.Repository

  @impl true
  def mount(_params, _session, socket) do
    communities_with_collections = Repository.list_communities_with_collections()

    {:ok,
     socket
     |> assign(:page_title, "Browse — Kiroku")
     |> assign(:communities, communities_with_collections)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_user}>
      <div class="space-y-10">
        <%!-- Page header --%>
        <div>
          <p
            class="text-sm font-medium uppercase tracking-widest mb-1"
            style="color: var(--color-patchouli);"
          >
            Browse
          </p>
          <h1 class="font-heading text-4xl font-semibold" style="color: var(--color-lilac);">
            Repository Structure
          </h1>
          <p class="mt-2 text-sm" style="color: var(--color-quill);">
            Knowledge organized by faculty, institute, and research unit.
          </p>
        </div>

        <%!-- Communities --%>
        <%= if @communities == [] do %>
          <div class="kiroku-card p-12 text-center">
            <span class="kiroku-kanji text-5xl opacity-30">記</span>
            <p class="mt-4" style="color: var(--color-quill);">
              No communities have been created yet.
            </p>
          </div>
        <% else %>
          <div class="space-y-8">
            <%= for community <- @communities do %>
              <div class="space-y-3">
                <%!-- Community header --%>
                <div class="kiroku-card p-5">
                  <div class="flex items-start gap-4">
                    <div
                      class="w-12 h-12 rounded-xl flex items-center justify-center shrink-0"
                      style="background: rgba(123,79,166,0.2); color: var(--color-patchouli);"
                    >
                      <.icon name="hero-academic-cap" class="w-6 h-6" />
                    </div>
                    <div class="flex-1 min-w-0">
                      <.link
                        navigate={~p"/communities/#{community.handle}"}
                        class="font-heading text-xl font-semibold hover:underline"
                        style="color: var(--color-lilac);"
                      >
                        {community.name}
                      </.link>
                      <p class="kiroku-handle mt-0.5">/{community.handle}</p>
                      <%= if community.short_description do %>
                        <p class="mt-1 text-sm" style="color: var(--color-quill);">
                          {community.short_description}
                        </p>
                      <% end %>
                    </div>
                  </div>
                </div>

                <%!-- Collections under this community --%>
                <%= if community.collections != [] do %>
                  <div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-3 ml-4">
                    <%= for collection <- community.collections do %>
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
                        <div class="min-w-0">
                          <p
                            class="font-medium text-sm group-hover:text-white transition-colors"
                            style="color: var(--color-lilac);"
                          >
                            {collection.name}
                          </p>
                          <p class="kiroku-handle text-xs">{collection.handle}</p>
                        </div>
                      </.link>
                    <% end %>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
