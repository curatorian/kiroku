defmodule KirokuWeb.Admin.DashboardLive do
  use KirokuWeb, :live_view

  alias Kiroku.{Accounts, Repository}

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_user}>
      <div class="space-y-8">
        <%!-- Page Header --%>
        <div class="flex items-center justify-between">
          <div>
            <h1 class="font-heading text-3xl" style="color: var(--color-lilac);">
              Admin Dashboard
            </h1>
            <p class="font-body text-sm mt-1" style="color: var(--color-quill);">
              Overview of repository activity and pending actions
            </p>
          </div>
          <%= if @stats.items_submitted > 0 do %>
            <.link
              navigate={~p"/admin/items?status=submitted"}
              class="flex items-center gap-2 px-4 py-2 rounded-lg font-semibold text-sm"
              style="background: rgba(196,65,90,0.15); color: var(--color-ribbon-red); border: 1px solid rgba(196,65,90,0.3);"
            >
              <span
                class="inline-flex items-center justify-center w-5 h-5 rounded-full text-xs font-bold"
                style="background: var(--color-ribbon-red); color: white;"
              >
                {@stats.items_submitted}
              </span>
              Pending Review
            </.link>
          <% end %>
        </div>

        <%!-- Stats Row --%>
        <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-4">
          <div class="kiroku-card p-5 text-center">
            <p class="font-heading text-4xl" style="color: var(--color-patchouli);">
              {@stats.communities}
            </p>
            <p
              class="font-ui text-xs uppercase tracking-widest mt-2"
              style="color: var(--color-quill);"
            >
              Communities
            </p>
          </div>
          <div class="kiroku-card p-5 text-center">
            <p class="font-heading text-4xl" style="color: var(--color-patchouli);">
              {@stats.collections}
            </p>
            <p
              class="font-ui text-xs uppercase tracking-widest mt-2"
              style="color: var(--color-quill);"
            >
              Collections
            </p>
          </div>
          <div class="kiroku-card p-5 text-center">
            <p class="font-heading text-4xl" style="color: var(--color-patchouli);">
              {@stats.items_total}
            </p>
            <p
              class="font-ui text-xs uppercase tracking-widest mt-2"
              style="color: var(--color-quill);"
            >
              Total Items
            </p>
          </div>
          <div class="kiroku-card p-5 text-center">
            <p class="font-heading text-4xl" style="color: #5A9E72;">
              {@stats.items_published}
            </p>
            <p
              class="font-ui text-xs uppercase tracking-widest mt-2"
              style="color: var(--color-quill);"
            >
              Published
            </p>
          </div>
          <div class={[
            "kiroku-card p-5 text-center",
            @stats.items_submitted > 0 && "ring-1 ring-red-500/30"
          ]}>
            <p
              class="font-heading text-4xl"
              style={
                if(@stats.items_submitted > 0,
                  do: "color: var(--color-ribbon-red);",
                  else: "color: var(--color-quill);"
                )
              }
            >
              {@stats.items_submitted}
            </p>
            <p
              class="font-ui text-xs uppercase tracking-widest mt-2"
              style="color: var(--color-quill);"
            >
              Pending
            </p>
          </div>
          <div class="kiroku-card p-5 text-center">
            <p class="font-heading text-4xl" style="color: var(--color-patchouli);">
              {@stats.users}
            </p>
            <p
              class="font-ui text-xs uppercase tracking-widest mt-2"
              style="color: var(--color-quill);"
            >
              Users
            </p>
          </div>
        </div>

        <%!-- Item Status Breakdown --%>
        <div class="kiroku-card p-5 space-y-3">
          <h2 class="font-heading text-base" style="color: var(--color-wisteria);">
            Item Status Breakdown
          </h2>
          <div class="flex flex-wrap gap-3">
            <.link
              patch={~p"/admin/items?status=draft"}
              class="flex items-center gap-2 px-3 py-1.5 rounded-lg text-xs font-medium transition-colors"
              style="background: rgba(155,126,200,0.08);"
            >
              <span class="status-badge draft">draft</span>
              <span style="color: var(--color-quill);">{@stats.items_draft}</span>
            </.link>
            <.link
              patch={~p"/admin/items?status=submitted"}
              class="flex items-center gap-2 px-3 py-1.5 rounded-lg text-xs font-medium transition-colors"
              style="background: rgba(155,126,200,0.08);"
            >
              <span class="status-badge submitted">submitted</span>
              <span style="color: var(--color-quill);">{@stats.items_submitted}</span>
            </.link>
            <.link
              patch={~p"/admin/items?status=published"}
              class="flex items-center gap-2 px-3 py-1.5 rounded-lg text-xs font-medium transition-colors"
              style="background: rgba(155,126,200,0.08);"
            >
              <span class="status-badge published">published</span>
              <span style="color: var(--color-quill);">{@stats.items_published}</span>
            </.link>
            <.link
              patch={~p"/admin/items?status=embargoed"}
              class="flex items-center gap-2 px-3 py-1.5 rounded-lg text-xs font-medium transition-colors"
              style="background: rgba(155,126,200,0.08);"
            >
              <span class="status-badge embargoed">embargoed</span>
              <span style="color: var(--color-quill);">{@stats.items_embargoed}</span>
            </.link>
            <.link
              patch={~p"/admin/items?status=withdrawn"}
              class="flex items-center gap-2 px-3 py-1.5 rounded-lg text-xs font-medium transition-colors"
              style="background: rgba(155,126,200,0.08);"
            >
              <span class="status-badge withdrawn">withdrawn</span>
              <span style="color: var(--color-quill);">{@stats.items_withdrawn}</span>
            </.link>
          </div>
        </div>

        <%!-- Two-column content --%>
        <div class="grid lg:grid-cols-3 gap-6">
          <%!-- Review Queue (2/3 width) --%>
          <div class="lg:col-span-2 space-y-4">
            <div class="flex items-center justify-between">
              <h2 class="font-heading text-xl" style="color: var(--color-lilac);">Review Queue</h2>
              <.link
                navigate={~p"/admin/items?status=submitted"}
                class="text-xs font-medium transition-colors hover:text-white"
                style="color: var(--color-lavender);"
              >
                View all →
              </.link>
            </div>

            <%= if @pending_items == [] do %>
              <div class="kiroku-card p-10 text-center">
                <p class="font-heading text-lg" style="color: var(--color-wisteria);">
                  All clear!
                </p>
                <p class="font-body text-sm mt-1" style="color: var(--color-quill);">
                  No items are currently awaiting review.
                </p>
              </div>
            <% else %>
              <div
                class="kiroku-card overflow-hidden divide-y"
                style="border-color: rgba(155,126,200,0.1);"
              >
                <%= for item <- @pending_items do %>
                  <div class="p-4 flex items-start gap-4">
                    <div class="flex-1 min-w-0">
                      <div class="flex items-center gap-2 mb-1 flex-wrap">
                        <span class="badge-item-type text-xs">{item.item_type}</span>
                        <%= if item.faculty do %>
                          <span
                            class="font-ui text-xs px-2 py-0.5 rounded"
                            style="background: rgba(155,126,200,0.1); color: var(--color-wisteria);"
                          >
                            {item.faculty}
                          </span>
                        <% end %>
                      </div>
                      <p class="font-body text-sm font-medium" style="color: var(--color-lilac);">
                        {item.title}
                      </p>
                      <div class="flex items-center gap-3 mt-1">
                        <%= if item.submitter do %>
                          <span class="font-ui text-xs" style="color: var(--color-quill);">
                            {item.submitter.display_name || item.submitter.email}
                          </span>
                        <% end %>
                        <span class="font-ui text-xs" style="color: var(--color-quill);">
                          {Calendar.strftime(item.inserted_at, "%d %b %Y")}
                        </span>
                      </div>
                    </div>
                    <.link
                      navigate={~p"/admin/items/#{item.id}"}
                      class="shrink-0 px-3 py-1.5 rounded-lg text-xs font-medium transition-colors"
                      style="background: rgba(155,126,200,0.12); color: var(--color-lavender);"
                    >
                      Review →
                    </.link>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>

          <%!-- Right sidebar (1/3 width) --%>
          <div class="space-y-6">
            <%!-- Quick Actions --%>
            <div class="space-y-3">
              <h2 class="font-heading text-xl" style="color: var(--color-lilac);">Quick Actions</h2>
              <div class="space-y-2">
                <.link
                  navigate={~p"/admin/communities"}
                  class="kiroku-card p-4 flex items-center gap-3 block transition-colors hover:border-purple-500/40"
                >
                  <span class="kiroku-kanji text-xl shrink-0" style="opacity: 0.5;">記</span>
                  <div>
                    <p class="font-heading text-sm" style="color: var(--color-lilac);">Communities</p>
                    <p class="font-ui text-xs" style="color: var(--color-quill);">
                      {@stats.communities} active
                    </p>
                  </div>
                </.link>
                <.link
                  navigate={~p"/admin/collections"}
                  class="kiroku-card p-4 flex items-center gap-3 block transition-colors hover:border-purple-500/40"
                >
                  <span class="kiroku-kanji text-xl shrink-0" style="opacity: 0.5;">集</span>
                  <div>
                    <p class="font-heading text-sm" style="color: var(--color-lilac);">Collections</p>
                    <p class="font-ui text-xs" style="color: var(--color-quill);">
                      {@stats.collections} total
                    </p>
                  </div>
                </.link>
                <.link
                  navigate={~p"/admin/items"}
                  class="kiroku-card p-4 flex items-center gap-3 block transition-colors hover:border-purple-500/40"
                >
                  <span class="kiroku-kanji text-xl shrink-0" style="opacity: 0.5;">本</span>
                  <div>
                    <p class="font-heading text-sm" style="color: var(--color-lilac);">All Items</p>
                    <p class="font-ui text-xs" style="color: var(--color-quill);">
                      {@stats.items_total} items across all statuses
                    </p>
                  </div>
                </.link>
                <.link
                  navigate={~p"/admin/users"}
                  class="kiroku-card p-4 flex items-center gap-3 block transition-colors hover:border-purple-500/40"
                >
                  <span class="kiroku-kanji text-xl shrink-0" style="opacity: 0.5;">人</span>
                  <div>
                    <p class="font-heading text-sm" style="color: var(--color-lilac);">Users</p>
                    <p class="font-ui text-xs" style="color: var(--color-quill);">
                      {@stats.users} registered accounts
                    </p>
                  </div>
                </.link>
              </div>
            </div>

            <%!-- Recently Published --%>
            <div class="space-y-3">
              <h2 class="font-heading text-xl" style="color: var(--color-lilac);">
                Recently Published
              </h2>
              <%= if @recent_published == [] do %>
                <p class="font-body text-sm" style="color: var(--color-quill);">
                  No published items yet.
                </p>
              <% else %>
                <div class="space-y-2">
                  <%= for item <- @recent_published do %>
                    <.link
                      navigate={~p"/admin/items/#{item.id}"}
                      class="kiroku-card p-3 block transition-colors hover:border-purple-500/40"
                    >
                      <div class="flex items-center gap-1.5 mb-1">
                        <span class="badge-item-type text-xs">{item.item_type}</span>
                      </div>
                      <p class="font-body text-xs line-clamp-2" style="color: var(--color-lilac);">
                        {item.title}
                      </p>
                      <%= if item.published_at do %>
                        <p class="font-ui text-xs mt-1" style="color: var(--color-quill);">
                          {Calendar.strftime(item.published_at, "%d %b %Y")}
                        </p>
                      <% end %>
                    </.link>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  def mount(_params, _session, socket) do
    stats = Repository.dashboard_stats()
    user_count = Accounts.count_users()

    {:ok,
     socket
     |> assign(:stats, Map.put(stats, :users, user_count))
     |> assign(:pending_items, Repository.list_pending_items(10))
     |> assign(:recent_published, Repository.list_recent_published(5))}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}
end
