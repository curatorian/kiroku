defmodule KirokuWeb.Admin.DashboardLive do
  use KirokuWeb, :live_view

  alias Kiroku.{Accounts, Repository}

  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_user} page_title="Dashboard">
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
                    <div class="flex-1 min-w-0 space-y-2">
                      <div class="flex items-center gap-2 mb-1 flex-wrap">
                        <span class="badge-item-type text-xs">{item.item_type}</span>
                        <span class="status-badge text-xs submitted">submitted</span>
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

                      <%!-- Abstract (truncated) --%>
                      <%= if item.abstract do %>
                        <% abstract_text = item.abstract

                        truncated_abstract =
                          if String.length(abstract_text) > 100 do
                            String.slice(abstract_text, 0, 97) <> "..."
                          else
                            abstract_text
                          end %>
                        <p
                          class="text-xs leading-relaxed line-clamp-2"
                          style="color: var(--color-quill);"
                        >
                          {truncated_abstract}
                        </p>
                      <% end %>

                      <%!-- Author information --%>
                      <%= if item.student_name do %>
                        <div class="flex items-center gap-2">
                          <div
                            class="w-6 h-6 rounded-full flex items-center justify-center shrink-0 text-[10px] font-bold"
                            style="background: rgba(123,79,166,0.2); color: var(--color-patchouli);"
                          >
                            {String.first(item.student_name)}
                          </div>
                          <div class="flex-1 min-w-0">
                            <p
                              class="font-medium text-xs truncate"
                              style="color: var(--color-wisteria);"
                            >
                              {item.student_name}
                            </p>
                            <%= if item.student_id do %>
                              <p
                                class="font-mono text-[10px] truncate"
                                style="color: var(--color-quill);"
                              >
                                NPM: {item.student_id}
                              </p>
                            <% end %>
                          </div>
                        </div>
                      <% end %>

                      <%!-- Academic information --%>
                      <div
                        class="flex flex-wrap gap-1.5 text-[10px]"
                        style="color: var(--color-quill);"
                      >
                        <%= if item.program_study do %>
                          <span
                            class="px-1.5 py-0.5 rounded"
                            style="background: rgba(155,126,200,0.06);"
                          >
                            {item.program_study}
                          </span>
                        <% end %>
                        <%= if item.submitter do %>
                          <span
                            class="px-1.5 py-0.5 rounded"
                            style="background: rgba(155,126,200,0.06);"
                          >
                            by {item.submitter.display_name || item.submitter.email}
                          </span>
                        <% end %>
                      </div>

                      <%!-- Date information --%>
                      <div class="flex items-center gap-1.5">
                        <.icon
                          name="hero-calendar"
                          class="w-3 h-3 shrink-0"
                          style="color: var(--color-dust);"
                        />
                        <span class="font-mono text-[10px]" style="color: var(--color-dust);">
                          Created: {Calendar.strftime(item.inserted_at, "%d %b %Y")}
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

            <%!-- Sync Health ─────────────────────────────────────────────── --%>
            <%= if @sync_health do %>
              <div class="space-y-3">
                <div class="flex items-center justify-between">
                  <h2 class="font-heading text-xl" style="color: var(--color-lilac);">
                    Sync Health
                  </h2>
                  <.link
                    navigate={~p"/admin/sync"}
                    class="text-xs font-medium transition-colors hover:text-white"
                    style="color: var(--color-lavender);"
                  >
                    Manage →
                  </.link>
                </div>
                <.link
                  navigate={~p"/admin/sync"}
                  class="kiroku-card p-4 block transition-colors hover:border-purple-500/40"
                >
                  <div class="space-y-2">
                    <div
                      :for={entry <- @sync_health.entries}
                      class="flex items-center justify-between"
                    >
                      <span class="text-xs" style="color: var(--color-quill);">
                        {entry.view}
                      </span>
                      <span class="flex items-center gap-1.5">
                        <span
                          class="w-2 h-2 rounded-full"
                          style={sync_dot_style(entry)}
                        />
                        <span class="text-xs" style="color: var(--color-quill);">
                          {sync_relative(entry)}
                        </span>
                      </span>
                    </div>
                  </div>
                  <%= if @sync_health.dead_letter_count > 0 do %>
                    <p
                      class="text-xs mt-3 pt-3"
                      style="color: var(--color-ribbon-red); border-top: 1px solid rgba(196,65,90,0.2);"
                    >
                      <.icon name="hero-exclamation-triangle" class="size-3.5 inline" />
                      {@sync_health.dead_letter_count} record(s) need attention
                    </p>
                  <% end %>
                </.link>
              </div>
            <% end %>

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
                      <p
                        class="font-body text-xs font-medium line-clamp-2"
                        style="color: var(--color-lilac);"
                      >
                        {item.title}
                      </p>

                      <%!-- Author information --%>
                      <%= if item.student_name do %>
                        <div class="flex items-center gap-1.5 mt-1">
                          <div
                            class="w-4 h-4 rounded-full flex items-center justify-center shrink-0 text-[8px] font-bold"
                            style="background: rgba(123,79,166,0.2); color: var(--color-patchouli);"
                          >
                            {String.first(item.student_name)}
                          </div>
                          <div class="flex-1 min-w-0">
                            <p
                              class="font-medium text-[10px] truncate"
                              style="color: var(--color-wisteria);"
                            >
                              {item.student_name}
                            </p>
                            <%= if item.student_id do %>
                              <p
                                class="font-mono text-[8px] truncate"
                                style="color: var(--color-quill);"
                              >
                                NPM: {item.student_id}
                              </p>
                            <% end %>
                          </div>
                        </div>
                      <% end %>

                      <%!-- Academic information --%>
                      <div
                        class="flex flex-wrap gap-1 mt-1 text-[8px]"
                        style="color: var(--color-quill);"
                      >
                        <%= if item.program_study do %>
                          <span
                            class="px-1 py-0.5 rounded"
                            style="background: rgba(155,126,200,0.06);"
                          >
                            {item.program_study}
                          </span>
                        <% end %>
                      </div>

                      <%= if item.published_at do %>
                        <div class="flex items-center gap-1 mt-1">
                          <.icon
                            name="hero-calendar"
                            class="w-2.5 h-2.5 shrink-0"
                            style="color: var(--color-dust);"
                          />
                          <span class="font-mono text-[8px]" style="color: var(--color-dust);">
                            {Calendar.strftime(item.published_at, "%d %b %Y")}
                          </span>
                        </div>
                      <% end %>
                    </.link>
                  <% end %>
                </div>
              <% end %>
            </div>

            <%!-- Fixity status --%>
            <div class="space-y-3">
              <h2 class="font-heading text-xl" style="color: var(--color-lilac);">
                File Integrity
              </h2>
              <div class="kiroku-card p-4 space-y-2 text-sm">
                <div class="flex justify-between">
                  <span style="color: var(--color-quill);">Verified OK</span>
                  <span class="font-mono" style="color: var(--color-patchouli);">
                    {@fixity.ok}
                  </span>
                </div>
                <div class="flex justify-between">
                  <span style="color: var(--color-quill);">Failed checks</span>
                  <span
                    class="font-mono"
                    style={
                      if @fixity.failed > 0,
                        do: "color: var(--color-ribbon-red);",
                        else: "color: var(--color-wisteria);"
                    }
                  >
                    {@fixity.failed}
                  </span>
                </div>
                <div class="flex justify-between">
                  <span style="color: var(--color-quill);">Never checked</span>
                  <span class="font-mono" style="color: var(--color-wisteria);">
                    {@fixity.unchecked}
                  </span>
                </div>
                <div class="flex justify-between">
                  <span style="color: var(--color-quill);">Externally hosted</span>
                  <span class="font-mono" style="color: var(--color-dust);">
                    {@fixity.unverifiable}
                  </span>
                </div>
                <p class="text-[10px] pt-1" style="color: var(--color-quill);">
                  Checked daily via <code>FixityWorker</code> (cron <code>FIXITY_CRON</code>).
                </p>
              </div>
            </div>

            <%!-- Popular (views + downloads) --%>
            <div class="space-y-3">
              <h2 class="font-heading text-xl" style="color: var(--color-lilac);">
                Popular
              </h2>
              <div class="kiroku-card p-4 space-y-3 text-sm">
                <div>
                  <p
                    class="text-[10px] uppercase tracking-wider mb-1"
                    style="color: var(--color-quill);"
                  >
                    Most viewed
                  </p>
                  <%= if @top_viewed == [] do %>
                    <p class="text-xs" style="color: var(--color-quill);">No views recorded yet.</p>
                  <% else %>
                    <ul class="space-y-1">
                      <li :for={entry <- @top_viewed} class="flex justify-between gap-2">
                        <.link
                          navigate={~p"/admin/items/#{entry.id}"}
                          class="truncate hover:underline"
                          style="color: var(--color-wisteria);"
                        >
                          {entry.title}
                        </.link>
                        <span class="font-mono shrink-0" style="color: var(--color-patchouli);">
                          {entry.views}
                        </span>
                      </li>
                    </ul>
                  <% end %>
                </div>
                <div>
                  <p
                    class="text-[10px] uppercase tracking-wider mb-1"
                    style="color: var(--color-quill);"
                  >
                    Most downloaded
                  </p>
                  <%= if @top_downloaded == [] do %>
                    <p class="text-xs" style="color: var(--color-quill);">
                      No downloads recorded yet.
                    </p>
                  <% else %>
                    <ul class="space-y-1">
                      <li :for={entry <- @top_downloaded} class="flex justify-between gap-2">
                        <.link
                          navigate={~p"/admin/items/#{entry.id}"}
                          class="truncate hover:underline"
                          style="color: var(--color-wisteria);"
                        >
                          {entry.title}
                        </.link>
                        <span class="font-mono shrink-0" style="color: var(--color-patchouli);">
                          {entry.downloads}
                        </span>
                      </li>
                    </ul>
                  <% end %>
                </div>
                <p class="text-[10px] pt-1" style="color: var(--color-quill);">
                  Counts exclude crawler user-agents.
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.admin>
    """
  end

  def mount(_params, _session, socket) do
    stats = Repository.dashboard_stats()
    user_count = Accounts.count_users()

    {:ok,
     socket
     |> assign(:stats, Map.put(stats, :users, user_count))
     |> assign(:pending_items, Repository.list_pending_items(10))
     |> assign(:recent_published, Repository.list_recent_published(limit: 5, scope: :staff))
     |> assign(:fixity, Kiroku.Content.fixity_summary())
     |> assign(:top_viewed, Kiroku.Analytics.top_viewed_with_items(5))
     |> assign(:top_downloaded, Kiroku.Analytics.top_downloaded_with_items(5))
     |> assign(:sync_enabled, Kiroku.Sync.enabled?())
     |> assign(:sync_health, maybe_sync_health())}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  # Compact sync health summary for the dashboard widget. Returns one entry
  # per legacy view with its latest run status, plus the unresolved dead-letter
  # count surfaced once (on the first entry / as a separate field).
  # Returns nil when MSSQL sync is not configured.
  defp maybe_sync_health do
    if Kiroku.Sync.enabled?(), do: sync_health_summary(), else: nil
  end

  defp sync_health_summary do
    import Ecto.Query

    views = Kiroku.Sync.Importer.views()

    latest_runs =
      views
      |> Enum.map(fn {view, _} -> to_string(view) end)
      |> Kiroku.Sync.get_latest_sync_runs()
      |> Enum.group_by(& &1.source_view)

    entries =
      Enum.map(views, fn {view, _} ->
        run = Map.get(latest_runs, to_string(view), []) |> List.first()

        %{
          view: view,
          status: run && run.status,
          started_at: run && run.started_at,
          failed: run && (run.records_failed || 0)
        }
      end)

    dead_letter_count =
      Kiroku.Repo.aggregate(
        from(d in Kiroku.Sync.DeadLetterQueue, where: is_nil(d.resolved_at)),
        :count
      )

    %{entries: entries, dead_letter_count: dead_letter_count}
  end

  # Renders a small colored dot indicating the health of a view's last run.
  defp sync_dot_style(%{status: nil}),
    do: "background: var(--color-quill); opacity: 0.4;"

  defp sync_dot_style(%{status: "running"}),
    do: "background: #7dd3fc;"

  defp sync_dot_style(%{status: "completed", failed: failed}) when failed > 0,
    do: "background: #fb923c;"

  defp sync_dot_style(%{status: "completed"}),
    do: "background: #6ee7b7;"

  defp sync_dot_style(%{status: "failed"}),
    do: "background: var(--color-ribbon-red);"

  defp sync_dot_style(_),
    do: "background: var(--color-quill); opacity: 0.4;"

  defp sync_relative(%{started_at: nil}), do: "never"

  defp sync_relative(%{started_at: dt}) do
    diff = DateTime.diff(DateTime.utc_now(), dt)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86_400)}d ago"
    end
  end
end
