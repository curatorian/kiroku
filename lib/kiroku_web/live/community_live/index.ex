defmodule KirokuWeb.CommunityLive.Index do
  use KirokuWeb, :live_view

  alias Kiroku.Repository
  alias Kiroku.Access.Authorization

  @impl true
  def mount(_params, _session, socket) do
    scope = Authorization.visibility_scope(socket.assigns[:current_user])
    communities = Repository.list_root_communities(scope: scope)

    {:ok,
     socket
     |> assign(:page_title, "Communities — Kiroku")
     |> assign(:communities, communities)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_user}>
      <div class="space-y-8">
        <%!-- Page header --%>
        <div>
          <p
            class="text-sm font-medium uppercase tracking-widest mb-1"
            style="color: var(--color-patchouli);"
          >
            Browse
          </p>
          <h1 class="font-heading text-4xl font-semibold" style="color: var(--color-lilac);">
            Communities
          </h1>
          <p class="mt-2 text-sm" style="color: var(--color-quill);">
            Explore knowledge organized by faculty, institute, and research unit.
          </p>
        </div>

        <%!-- Community grid --%>
        <%= if @communities == [] do %>
          <div class="kiroku-card p-12 text-center">
            <span class="kiroku-kanji text-5xl opacity-30">記</span>
            <p class="mt-4" style="color: var(--color-quill);">
              No communities have been created yet.
            </p>
          </div>
        <% else %>
          <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            <%= for community <- @communities do %>
              <.link
                navigate={~p"/communities/#{community.handle}"}
                class="kiroku-card p-5 block hover:border-purple-500/40 transition-colors group"
              >
                <div class="flex items-start gap-3">
                  <div
                    class="w-10 h-10 rounded-lg flex items-center justify-center shrink-0"
                    style="background: rgba(123,79,166,0.2); color: var(--color-patchouli);"
                  >
                    <.icon name="hero-academic-cap" class="w-5 h-5" />
                  </div>
                  <div class="min-w-0">
                    <h2
                      class="font-heading text-lg leading-tight group-hover:text-white transition-colors"
                      style="color: var(--color-lilac);"
                    >
                      {community.name}
                    </h2>
                    <p class="kiroku-handle mt-1">/{community.handle}</p>
                    <%= if community.short_description do %>
                      <p
                        class="mt-2 text-sm leading-relaxed line-clamp-2"
                        style="color: var(--color-quill);"
                      >
                        {community.short_description}
                      </p>
                    <% end %>
                  </div>
                </div>
              </.link>
            <% end %>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
