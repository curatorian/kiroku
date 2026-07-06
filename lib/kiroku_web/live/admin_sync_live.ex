defmodule KirokuWeb.AdminSyncLive do
  @moduledoc """
  Staff dashboard for monitoring and triggering MSSQL sync/import jobs.

  Mounted at `/admin/sync`. Restricted to admins and superadmins. Shows live
  stats, recent runs, dead-letter queue, and exposes:
    - incremental sync per view (enqueues `MssqlSyncWorker`)
    - full import per view / all views (enqueues `ImportWorker`)
    - dry-run import (validate without persisting)
    - retry / resolve dead-letter records
  """

  use KirokuWeb, :live_view

  alias Kiroku.{LegacyRepo, Repo, Sync}
  alias Kiroku.Sync.DeadLetterQueue
  alias Kiroku.Workers.{ImportWorker, MssqlSyncWorker}
  import Ecto.Query

  @refresh_interval_ms 5_000

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_user} page_title="Sync &amp; Import">
      <div class="space-y-8">
        <%!-- Header ──────────────────────────────────────────────────────── --%>
        <div class="flex items-center justify-between flex-wrap gap-3">
          <div>
            <h1 class="font-heading text-3xl" style="color: var(--color-lilac);">
              Sync &amp; Import
            </h1>
            <p class="font-body text-sm mt-1" style="color: var(--color-quill);">
              Synchronize and import legacy records from MSSQL. Auto-refreshes every 5s while jobs run.
            </p>
          </div>
          <div class="flex items-center gap-2">
            {render_mssql_connection_status(assigns)}
            <span
              :if={has_active_runs?(assigns)}
              class="text-xs px-2.5 py-1 rounded-full animate-pulse"
              style="background: rgba(125,211,252,0.15); color: #7dd3fc;"
            >
              <.icon name="hero-arrow-path" class="size-3 inline" /> running…
            </span>
            <button
              phx-click="refresh"
              class="flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-sm font-medium transition-colors hover:brightness-110"
              style="background: rgba(155,126,200,0.12); color: var(--color-lavender);"
            >
              <.icon name="hero-arrow-path" class="size-4" /> Refresh
            </button>
          </div>
        </div>

        <%!-- Stats cards ────────────────────────────────────────────────── --%>
        <div class="grid grid-cols-2 lg:grid-cols-4 gap-4">
          <.sync_stat_card
            label="Total Runs"
            value={stat_value(@sync_stats, "total_runs")}
            icon="hero-arrow-path"
            tint="patchouli"
          />
          <.sync_stat_card
            label="Successful"
            value={stat_value(@sync_stats, "completed_runs")}
            icon="hero-check-circle"
            tint="emerald"
          />
          <.sync_stat_card
            label="Failed"
            value={stat_value(@sync_stats, "failed_runs")}
            icon="hero-exclamation-circle"
            tint="red"
          />
          <.sync_stat_card
            label="Records Processed"
            value={stat_value(@sync_stats, "total_records_processed")}
            icon="hero-document-text"
            tint="patchouli"
          />
        </div>

        <div class="grid lg:grid-cols-2 gap-6">
          <%!-- Sync controls (incremental) ─────────────────────────────── --%>
          <div class="kiroku-card p-6 space-y-4">
            <div class="flex items-center gap-2">
              <span style="color: var(--color-patchouli);">
                <.icon name="hero-arrow-path" class="size-5" />
              </span>
              <h2 class="font-heading text-lg" style="color: var(--color-lilac);">
                Incremental Sync
              </h2>
            </div>
            <p class="text-xs" style="color: var(--color-quill);">
              Only processes records that are new or have changed since the last run. Safe to run often.
            </p>
            <div class="grid grid-cols-2 gap-2">
              <button
                :for={{view, _type} <- @views}
                phx-click="trigger_sync"
                phx-value-view={view}
                class="px-3 py-2 rounded-lg text-sm font-medium transition-all hover:brightness-110 active:scale-95"
                style="background: rgba(45,212,191,0.15); color: #5eead4; border: 1px solid rgba(45,212,191,0.25);"
              >
                <.icon name="hero-arrow-path" class="size-3.5 inline mr-1" /> {view}
              </button>
            </div>
            <button
              phx-click="trigger_sync_all"
              class="w-full px-3 py-2 rounded-lg text-sm font-semibold transition-all hover:brightness-110 active:scale-95"
              style="background: var(--color-patchouli); color: white;"
            >
              Sync all views
            </button>
          </div>

          <%!-- Import controls (full) ──────────────────────────────────── --%>
          <div class="kiroku-card p-6 space-y-4">
            <div class="flex items-center gap-2">
              <span style="color: var(--color-patchouli);">
                <.icon name="hero-cloud-arrow-down" class="size-5" />
              </span>
              <h2 class="font-heading text-lg" style="color: var(--color-lilac);">
                Full Import
              </h2>
            </div>
            <p class="text-xs" style="color: var(--color-quill);">
              Re-processes <strong>every</strong>
              record in a view. Use for initial loads or forcing re-sync.
            </p>

            <label class="flex items-center gap-2.5 cursor-pointer select-none">
              <input
                type="checkbox"
                phx-click="toggle_dry_run"
                phx-value-dry_run={!@dry_run}
                checked={@dry_run}
                class="h-4 w-4 rounded"
                style="accent-color: var(--color-patchouli);"
              />
              <span class="text-sm" style="color: var(--color-wisteria);">
                Dry run (validate only — no writes)
              </span>
            </label>

            <div class="grid grid-cols-2 gap-2">
              <button
                :for={{view, _type} <- @views}
                phx-click="trigger_import"
                phx-value-view={view}
                class={[
                  "px-3 py-2 rounded-lg text-sm font-medium transition-all hover:brightness-110 active:scale-95 border",
                  if(@dry_run,
                    do: "bg-amber-500/15 text-amber-300 border-amber-500/30",
                    else: "bg-purple-500/15 text-purple-300 border-purple-500/30"
                  )
                ]}
              >
                {view}
              </button>
            </div>
            <button
              phx-click="trigger_import_all"
              class={[
                "w-full px-3 py-2 rounded-lg text-sm font-semibold transition-all hover:brightness-110 active:scale-95",
                if(@dry_run,
                  do: "bg-amber-500 text-white",
                  else: "bg-purple-500 text-white"
                )
              ]}
            >
              {if(@dry_run, do: "Dry-run import all views", else: "Import all views")}
            </button>
          </div>
        </div>

        <%!-- DSpace SAF export / import ─────────────────────────────────── --%>
        <div class="grid lg:grid-cols-2 gap-6">
          <%!-- SAF Export ─────────────────────────────────────────────── --%>
          <div class="kiroku-card p-6 space-y-4">
            <div class="flex items-center gap-2">
              <span style="color: var(--color-patchouli);">
                <.icon name="hero-arrow-up-tray" class="size-5" />
              </span>
              <h2 class="font-heading text-lg" style="color: var(--color-lilac);">
                DSpace SAF Export
              </h2>
            </div>
            <p class="text-xs" style="color: var(--color-quill);">
              Export a collection to a downloadable DSpace Simple Archive zip (metadata + files).
            </p>

            <form phx-change="saf_select_collection" class="space-y-3">
              <label class="block text-xs uppercase tracking-wider" style="color: var(--color-quill);">
                Collection
              </label>
              <select name="collection" class="kiroku-search-input w-full">
                <option value="">— Select collection —</option>
                <option
                  :for={{name, handle} <- @collections}
                  value={handle}
                  selected={handle == @saf_collection}
                >
                  {name}
                </option>
              </select>
            </form>

            <div class="flex gap-2">
              <button
                phx-click="saf_export"
                phx-value-collection={@saf_collection}
                phx-value-scope="published"
                disabled={@saf_collection == ""}
                class="flex-1 px-3 py-2 rounded-lg text-sm font-medium transition-all hover:brightness-110 active:scale-95 disabled:opacity-40 disabled:cursor-not-allowed"
                style="background: rgba(16,185,129,0.15); color: #6ee7b7; border: 1px solid rgba(16,185,129,0.25);"
              >
                Export published
              </button>
              <button
                phx-click="saf_export"
                phx-value-collection={@saf_collection}
                phx-value-scope="all"
                disabled={@saf_collection == ""}
                class="flex-1 px-3 py-2 rounded-lg text-sm font-medium transition-all hover:brightness-110 active:scale-95 disabled:opacity-40 disabled:cursor-not-allowed"
                style="background: rgba(155,126,200,0.15); color: var(--color-lavender); border: 1px solid rgba(155,126,200,0.25);"
              >
                Export all
              </button>
            </div>
          </div>

          <%!-- SAF Import ─────────────────────────────────────────────── --%>
          <div class="kiroku-card p-6 space-y-4">
            <div class="flex items-center gap-2">
              <span style="color: var(--color-patchouli);">
                <.icon name="hero-arrow-down-tray" class="size-5" />
              </span>
              <h2 class="font-heading text-lg" style="color: var(--color-lilac);">
                DSpace SAF Import
              </h2>
            </div>
            <p class="text-xs" style="color: var(--color-quill);">
              Upload a SAF zip. Items are upserted by handle (re-importing updates existing items).
            </p>

            <form phx-submit="saf_import" phx-change="saf_validate" class="space-y-3">
              <.live_file_input upload={@uploads.saf_archive} class="hidden" />

              <div
                :for={entry <- @uploads.saf_archive.entries}
                class="flex items-center justify-between px-3 py-2 rounded-lg"
                style="background: rgba(155,126,200,0.08);"
              >
                <span class="text-sm truncate" style="color: var(--color-lilac);">
                  {entry.client_name}
                </span>
                <button
                  type="button"
                  phx-click="saf_cancel_upload"
                  phx-value-ref={entry.ref}
                  class="text-xs px-2"
                  style="color: var(--color-ribbon-red);"
                >
                  <.icon name="hero-x-mark" class="size-4" />
                </button>
              </div>

              <label class="block text-xs uppercase tracking-wider" style="color: var(--color-quill);">
                Override collection (optional)
              </label>
              <select
                name="collection"
                class="kiroku-search-input w-full"
                phx-change="saf_select_collection"
              >
                <option value="">— Use archive's collections file —</option>
                <option
                  :for={{name, handle} <- @collections}
                  value={handle}
                  selected={handle == @saf_collection}
                >
                  {name}
                </option>
              </select>

              <label class="flex items-center gap-2.5 cursor-pointer select-none">
                <input
                  type="checkbox"
                  phx-click="saf_toggle_import_dry_run"
                  phx-value-dry_run={!@saf_import_dry_run}
                  checked={@saf_import_dry_run}
                  class="h-4 w-4 rounded"
                  style="accent-color: var(--color-patchouli);"
                />
                <span class="text-sm" style="color: var(--color-wisteria);">
                  Dry run (validate only)
                </span>
              </label>

              <button
                type="submit"
                class="w-full px-3 py-2 rounded-lg text-sm font-semibold transition-all hover:brightness-110 active:scale-95"
                style="background: var(--color-patchouli); color: white;"
              >
                {if(@saf_import_dry_run, do: "Dry-run import", else: "Import archive")}
              </button>
            </form>
          </div>
        </div>

        <%!-- Available SAF exports (download links) ─────────────────────── --%>
        <div :if={@saf_exports != []} class="kiroku-card overflow-hidden">
          <div class="p-5" style="border-bottom: 1px solid rgba(155,126,200,0.12);">
            <h2 class="font-heading text-base" style="color: var(--color-wisteria);">
              Exported Archives
            </h2>
          </div>
          <ul>
            <li
              :for={exp <- @saf_exports}
              class="flex items-center justify-between px-5 py-3"
              style="border-top: 1px solid rgba(155,126,200,0.08);"
            >
              <div class="min-w-0">
                <p class="text-sm font-medium truncate" style="color: var(--color-lilac);">
                  {Path.basename(exp.path)}
                </p>
                <p class="text-xs" style="color: var(--color-quill);">
                  {format_file_size(exp.size)}
                </p>
              </div>
              <.link
                href={~p"/admin/saf/download/#{exp.job_id}"}
                download
                class="flex items-center gap-1.5 text-xs font-medium px-3 py-1.5 rounded-lg transition-colors hover:brightness-110"
                style="background: rgba(16,185,129,0.15); color: #6ee7b7;"
              >
                <.icon name="hero-arrow-down-tray" class="size-3.5" /> Download
              </.link>
            </li>
          </ul>
        </div>

        <%!-- MSSQL Connection Status ─────────────────────────────────────── --%>
        <div class="kiroku-card p-6 space-y-4">
          <div class="flex items-center gap-2">
            {render_connection_icon(assigns.mssql_connection_status)}
            <h2 class="font-heading text-lg" style="color: var(--color-lilac);">
              MSSQL Connection Status
            </h2>
          </div>
          <div class="space-y-2">
            <p class="text-sm font-medium" style="color: var(--color-wisteria);">
              {@mssql_connection_status.message}
            </p>
            <p class="text-xs" style="color: var(--color-quill);">
              {@mssql_connection_status.details}
            </p>
            {render_connection_details(assigns.mssql_connection_status)}
          </div>
        </div>

        <%!-- Per-view statistics ────────────────────────────────────────── --%>
        <div class="kiroku-card overflow-hidden">
          <div class="p-5" style="border-bottom: 1px solid rgba(155,126,200,0.12);">
            <h2 class="font-heading text-base" style="color: var(--color-wisteria);">
              Per-View Statistics
            </h2>
          </div>
          <div class="overflow-x-auto">
            <table class="w-full text-sm">
              <thead>
                <tr
                  class="text-left text-xs uppercase tracking-wider"
                  style="color: var(--color-quill);"
                >
                  <th class="px-5 py-3">View</th>
                  <th class="px-3 py-3">Runs</th>
                  <th class="px-3 py-3">Inserted</th>
                  <th class="px-3 py-3">Updated</th>
                  <th class="px-3 py-3">Failed</th>
                  <th class="px-5 py-3">Last Run</th>
                </tr>
              </thead>
              <tbody>
                <tr :if={@sync_stats == []} style="border-top: 1px solid rgba(155,126,200,0.08);">
                  <td colspan="6" class="px-5 py-8 text-center" style="color: var(--color-quill);">
                    No sync runs recorded yet.
                  </td>
                </tr>
                <tr
                  :for={stat <- @sync_stats}
                  style="border-top: 1px solid rgba(155,126,200,0.08);"
                >
                  <td class="px-5 py-3 font-medium" style="color: var(--color-lilac);">
                    {stat["source_view"]}
                  </td>
                  <td class="px-3 py-3" style="color: var(--color-quill);">{stat["total_runs"]}</td>
                  <td class="px-3 py-3 text-emerald-300">{stat["total_records_inserted"]}</td>
                  <td class="px-3 py-3 text-sky-300">{stat["total_records_updated"]}</td>
                  <td class="px-3 py-3 text-red-300">{stat["total_records_failed"]}</td>
                  <td class="px-5 py-3 text-xs" style="color: var(--color-quill);">
                    {format_datetime(stat["last_run_at"])}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <%!-- Recent runs ─────────────────────────────────────────────────── --%>
        <div class="kiroku-card overflow-hidden">
          <div class="p-5" style="border-bottom: 1px solid rgba(155,126,200,0.12);">
            <h2 class="font-heading text-base" style="color: var(--color-wisteria);">
              Recent Runs
            </h2>
          </div>
          <div class="overflow-x-auto">
            <table class="w-full text-sm">
              <thead>
                <tr
                  class="text-left text-xs uppercase tracking-wider"
                  style="color: var(--color-quill);"
                >
                  <th class="px-5 py-3">View</th>
                  <th class="px-3 py-3">Type</th>
                  <th class="px-3 py-3">Status</th>
                  <th class="px-3 py-3">Started</th>
                  <th class="px-3 py-3">Duration</th>
                  <th class="px-3 py-3">Ins / Upd / Fail</th>
                </tr>
              </thead>
              <tbody>
                <tr :if={@recent_runs == []} style="border-top: 1px solid rgba(155,126,200,0.08);">
                  <td colspan="6" class="px-5 py-8 text-center" style="color: var(--color-quill);">
                    No sync runs yet. Trigger a sync or import to get started.
                  </td>
                </tr>
                <tr
                  :for={run <- @recent_runs}
                  style="border-top: 1px solid rgba(155,126,200,0.08);"
                >
                  <td class="px-5 py-3 font-medium" style="color: var(--color-lilac);">
                    {run.source_view}
                  </td>
                  <%!-- run_type badge --%>
                  <% {type_label, type_class} = run_type_badge(run) %>
                  <td class="px-3 py-3">
                    <span class={"text-xs px-2 py-0.5 rounded-full border #{type_class}"}>
                      {type_label}
                    </span>
                  </td>
                  <td class="px-3 py-3">
                    <span class={"text-xs px-2 py-0.5 rounded-full border #{run_status_badge(run.status)}"}>
                      {run.status}
                    </span>
                  </td>
                  <td class="px-3 py-3 text-xs" style="color: var(--color-quill);">
                    {format_datetime(run.started_at)}
                  </td>
                  <td class="px-3 py-3 text-xs" style="color: var(--color-quill);">
                    {format_duration(run.started_at, run.completed_at)}
                  </td>
                  <td class="px-3 py-3 text-xs">
                    <span class="text-emerald-300">{run.records_inserted || 0}</span>
                    <span style="color: var(--color-quill);"> / </span>
                    <span class="text-sky-300">{run.records_updated || 0}</span>
                    <span style="color: var(--color-quill);"> / </span>
                    <span class="text-red-300">{run.records_failed || 0}</span>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <%!-- Dead letter queue ──────────────────────────────────────────── --%>
        <div
          :if={@dead_letter_queue != []}
          class="kiroku-card overflow-hidden"
          style="border-color: rgba(249,115,22,0.25);"
        >
          <div
            class="p-5 flex items-center justify-between flex-wrap gap-2"
            style="border-bottom: 1px solid rgba(249,115,22,0.2);"
          >
            <h2 class="font-heading text-base" style="color: #fb923c;">
              Dead Letter Queue
              <span class="text-xs font-normal ml-2" style="color: var(--color-quill);">
                ({length(@dead_letter_queue)} unresolved)
              </span>
            </h2>
            <span class="text-xs" style="color: var(--color-quill);">
              Records requiring manual intervention
            </span>
          </div>
          <div class="overflow-x-auto">
            <table class="w-full text-sm">
              <thead>
                <tr
                  class="text-left text-xs uppercase tracking-wider"
                  style="color: var(--color-quill);"
                >
                  <th class="px-5 py-3">Legacy ID</th>
                  <th class="px-3 py-3">Category</th>
                  <th class="px-3 py-3">Retries</th>
                  <th class="px-3 py-3">First Failed</th>
                  <th class="px-3 py-3">Error</th>
                  <th class="px-5 py-3 text-right">Actions</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={dl <- @dead_letter_queue}
                  style="border-top: 1px solid rgba(155,126,200,0.08);"
                >
                  <td class="px-5 py-3 font-mono text-xs" style="color: var(--color-lilac);">
                    {dl.legacy_id}
                  </td>
                  <td class="px-3 py-3">
                    <span class={"text-xs px-2 py-0.5 rounded-full border #{error_category_badge(dl.error_category)}"}>
                      {dl.error_category}
                    </span>
                  </td>
                  <td class="px-3 py-3" style="color: var(--color-quill);">{dl.retry_count}</td>
                  <td class="px-3 py-3 text-xs" style="color: var(--color-quill);">
                    {format_datetime(dl.first_failed_at)}
                  </td>
                  <td class="px-3 py-3 text-xs text-red-300 max-w-md truncate">
                    {dl.error_message}
                  </td>
                  <td class="px-5 py-3 text-right whitespace-nowrap">
                    <button
                      phx-click="retry_dead_letter"
                      phx-value-id={dl.id}
                      class="text-xs font-medium px-2 py-1 rounded transition-colors hover:brightness-110"
                      style="color: #7dd3fc;"
                    >
                      Retry
                    </button>
                    <button
                      phx-click="resolve_dead_letter"
                      phx-value-id={dl.id}
                      data-confirm="Mark this record as manually resolved?"
                      class="text-xs font-medium px-2 py-1 rounded transition-colors hover:brightness-110"
                      style="color: #6ee7b7;"
                    >
                      Resolve
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <%!-- Recent failed records ──────────────────────────────────────── --%>
        <div
          :if={@failed_records != []}
          class="kiroku-card overflow-hidden"
          style="border-color: rgba(196,65,90,0.2);"
        >
          <div class="p-5" style="border-bottom: 1px solid rgba(196,65,90,0.15);">
            <h2 class="font-heading text-base" style="color: var(--color-ribbon-red);">
              Recent Failed Records
            </h2>
          </div>
          <div class="overflow-x-auto">
            <table class="w-full text-sm">
              <thead>
                <tr
                  class="text-left text-xs uppercase tracking-wider"
                  style="color: var(--color-quill);"
                >
                  <th class="px-5 py-3">Legacy ID</th>
                  <th class="px-3 py-3">Synced At</th>
                  <th class="px-5 py-3">Error</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={rec <- @failed_records}
                  style="border-top: 1px solid rgba(155,126,200,0.08);"
                >
                  <td class="px-5 py-3 font-mono text-xs" style="color: var(--color-lilac);">
                    {rec.legacy_id}
                  </td>
                  <td class="px-3 py-3 text-xs" style="color: var(--color-quill);">
                    {format_datetime(rec.synced_at)}
                  </td>
                  <td class="px-5 py-3 text-xs text-red-300 max-w-lg truncate">
                    {rec.error_message}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </Layouts.admin>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if staff?(socket) do
      socket =
        socket
        |> allow_upload(:saf_archive,
          accept: ~w(.zip),
          max_entries: 1,
          max_file_size: 500_000_000,
          auto_upload: false
        )
        |> assign_sync_data()
        |> assign(:dry_run, false)
        |> assign(:saf_collection, "")
        |> assign(:saf_import_dry_run, false)
        |> schedule_refresh()

      {:ok, socket}
    else
      {:ok,
       socket
       |> put_flash(:error, "Only staff may access the sync dashboard.")
       |> push_navigate(to: ~p"/admin")}
    end
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event("refresh", _, socket) do
    {:noreply, assign_sync_data(socket)}
  end

  def handle_event("toggle_dry_run", %{"dry_run" => dry_run?}, socket) do
    {:noreply, assign(socket, :dry_run, dry_run? == "true")}
  end

  # ── Incremental sync (manual) ──────────────────────────────────────────────

  def handle_event("trigger_sync", %{"view" => view}, socket) do
    enqueue_job(MssqlSyncWorker, %{"view" => view}, socket, "Sync queued for #{view}")
  end

  def handle_event("trigger_sync_all", _, socket) do
    Kiroku.Sync.Importer.views()
    |> Enum.each(fn {view, _} ->
      %{view: view, triggered_by: triggered_by(socket)}
      |> MssqlSyncWorker.new()
      |> Oban.insert()
    end)

    {:noreply,
     socket
     |> put_flash(:info, "Sync queued for all views.")
     |> assign_sync_data()
     |> schedule_refresh()}
  end

  # ── Full import ────────────────────────────────────────────────────────────

  def handle_event("trigger_import", %{"view" => view}, socket) do
    args = %{
      "view" => view,
      "dry_run" => socket.assigns.dry_run,
      "triggered_by" => triggered_by(socket)
    }

    enqueue_job(ImportWorker, args, socket, import_flash(socket, view))
  end

  def handle_event("trigger_import_all", _, socket) do
    args = %{
      "view" => "all",
      "dry_run" => socket.assigns.dry_run,
      "triggered_by" => triggered_by(socket)
    }

    enqueue_job(ImportWorker, args, socket, import_flash(socket, "all views"))
  end

  # ── DSpace SAF export / import ─────────────────────────────────────────────

  def handle_event("saf_export", %{"collection" => collection_handle, "scope" => scope}, socket) do
    args = %{
      "target" => "collection",
      "id" => collection_handle,
      "only" => scope,
      "triggered_by" => triggered_by(socket)
    }

    enqueue_job(
      Kiroku.Workers.SafExportWorker,
      args,
      socket,
      "SAF export queued — the zip will appear below when ready."
    )
  end

  def handle_event("saf_select_collection", %{"collection" => handle}, socket) do
    {:noreply, assign(socket, :saf_collection, handle)}
  end

  def handle_event("saf_toggle_import_dry_run", %{"dry_run" => dry?}, socket) do
    {:noreply, assign(socket, :saf_import_dry_run, dry? == "true")}
  end

  def handle_event("saf_validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("saf_cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :saf_archive, ref)}
  end

  def handle_event("saf_import", _params, socket) do
    case consume_uploaded_entries(socket, :saf_archive, fn %{path: path}, _entry ->
           # Move the upload into a stable location the worker can read.
           dest = Path.join(Kiroku.Saf.imports_dir(), "#{Ecto.UUID.generate()}.zip")
           File.mkdir_p!(Kiroku.Saf.imports_dir())
           File.cp!(path, dest)
           {:ok, dest}
         end) do
      [source] ->
        args = %{
          "source" => source,
          "dry_run" => socket.assigns.saf_import_dry_run,
          "triggered_by" => triggered_by(socket)
        }

        args =
          if socket.assigns.saf_collection != "",
            do: Map.put(args, "collection", socket.assigns.saf_collection),
            else: args

        enqueue_job(
          Kiroku.Workers.SafImportWorker,
          args,
          socket,
          if(socket.assigns.saf_import_dry_run,
            do: "SAF dry-run import queued.",
            else: "SAF import queued — check item counts after it completes."
          )
        )

      [] ->
        {:noreply, put_flash(socket, :error, "Choose a SAF zip file first.")}
    end
  end

  # ── Dead-letter queue ──────────────────────────────────────────────────────

  def handle_event("retry_dead_letter", %{"id" => id}, socket) do
    dead_letter = Repo.get!(DeadLetterQueue, id)

    result =
      Sync.ErrorHandler.schedule_retry(
        dead_letter.sync_run_id,
        dead_letter.legacy_id,
        dead_letter.error_message,
        dead_letter.retry_count + 1,
        String.to_existing_atom(dead_letter.error_category)
      )

    flash =
      case result do
        {:ok, _} -> "Retry scheduled for #{dead_letter.legacy_id}."
        {:error, _} -> "Could not schedule retry."
      end

    {:noreply,
     socket
     |> put_flash(:info, flash)
     |> assign_sync_data()}
  end

  def handle_event("resolve_dead_letter", %{"id" => id}, socket) do
    dead_letter = Repo.get!(DeadLetterQueue, id)

    dead_letter
    |> Ecto.Changeset.change(%{
      resolved_at: DateTime.utc_now(),
      resolution_notes: "Manually resolved via dashboard"
    })
    |> Repo.update()

    {:noreply,
     socket
     |> put_flash(:info, "Record marked as resolved.")
     |> assign_sync_data()}
  end

  # ── Auto-refresh ───────────────────────────────────────────────────────────

  @impl true
  def handle_info(:refresh, socket) do
    socket =
      socket
      |> assign_sync_data()
      |> schedule_refresh()

    {:noreply, socket}
  end

  defp schedule_refresh(socket) do
    if has_active_runs?(socket.assigns) do
      Process.send_after(self(), :refresh, @refresh_interval_ms)
    end

    socket
  end

  # Accepts the assigns map (works both from render, where `assigns` is passed,
  # and from mount/handle_info via `socket.assigns`).
  defp has_active_runs?(assigns) when is_map(assigns) do
    Enum.any?(assigns[:recent_runs] || [], &(&1.status in ["pending", "running"]))
  end

  # ── Data loading ───────────────────────────────────────────────────────────

  defp assign_sync_data(socket) do
    stats = Sync.get_sync_stats()
    recent_runs = Sync.list_sync_runs(limit: 15)
    failed_records = recent_failed_records(recent_runs)
    dead_letter_queue = unresolved_dead_letters(50)
    mssql_connection_status = check_mssql_connection()

    assign(socket, %{
      sync_stats: stats,
      recent_runs: recent_runs,
      failed_records: failed_records,
      dead_letter_queue: dead_letter_queue,
      views: Kiroku.Sync.Importer.views(),
      collections:
        Repo.all(
          from c in Kiroku.Repository.Collection, order_by: c.name, select: {c.name, c.handle}
        ),
      saf_exports: Kiroku.Saf.list_exports(),
      mssql_connection_status: mssql_connection_status
    })
  end

  defp check_mssql_connection do
    config = LegacyRepo.Inspector.get_config()

    cond do
      !config.configured? ->
        %{
          status: :not_configured,
          message: "MSSQL connection not configured",
          details:
            "Please set MSSQL_HOST, MSSQL_DB, MSSQL_USER, and MSSQL_PASS environment variables"
        }

      true ->
        case LegacyRepo.Inspector.test_connection() do
          {:ok, info} ->
            %{
              status: :connected,
              message: "Connected to MSSQL",
              details: "Database: #{info.database} on #{info.hostname}:#{info.port}",
              version: info.version
            }

          {:error, :repo_not_started} ->
            %{
              status: :error,
              message: "LegacyRepo not started",
              details: "The MSSQL connection could not be established"
            }

          {:error, :connection_failed} ->
            %{
              status: :error,
              message: "Connection failed",
              details: "Unable to reach MSSQL server - check network and credentials"
            }

          {:error, reason} ->
            %{
              status: :error,
              message: "Connection error",
              details: inspect(reason)
            }
        end
    end
  end

  defp recent_failed_records(sync_runs) do
    sync_runs
    |> Enum.filter(&(&1.status == "failed" or &1.records_failed > 0))
    |> Enum.flat_map(fn run -> Sync.list_failed_records(run.id, limit: 5) end)
    |> Enum.take(20)
  end

  defp unresolved_dead_letters(limit) do
    Repo.all(
      from d in DeadLetterQueue,
        where: is_nil(d.resolved_at),
        order_by: [desc: d.first_failed_at],
        limit: ^limit
    )
  end

  # ── Authorization ──────────────────────────────────────────────────────────

  defp staff?(socket) do
    user = socket.assigns[:current_user]
    user && user.user_type in [:admin, :superadmin]
  end

  defp triggered_by(socket) do
    user = socket.assigns[:current_user]
    user && user.id
  end

  # ── Job enqueue helper ─────────────────────────────────────────────────────

  defp enqueue_job(worker, args, socket, flash) do
    case args |> worker.new() |> Oban.insert() do
      {:ok, _job} ->
        {:noreply,
         socket
         |> put_flash(:info, flash)
         |> assign_sync_data()
         |> schedule_refresh()}

      {:error, _changeset} ->
        {:noreply,
         put_flash(socket, :error, "Could not queue the job. It may already be running.")}
    end
  end

  defp import_flash(socket, target) do
    if socket.assigns.dry_run,
      do: "Dry-run import queued for #{target} (nothing will be written).",
      else: "Full import queued for #{target}."
  end

  # ── Render helpers ─────────────────────────────────────────────────────────

  def format_datetime(nil), do: "Never"

  def format_datetime(dt) do
    dt
    |> DateTime.shift_zone!("Asia/Jakarta")
    |> Calendar.strftime("%Y-%m-%d %H:%M:%S")
  end

  def format_duration(nil, nil), do: "—"
  def format_duration(nil, _), do: "—"
  def format_duration(_, nil), do: "—"

  def format_duration(started, completed) do
    diff = DateTime.diff(completed, started)
    minutes = div(diff, 60)
    seconds = rem(diff, 60)

    cond do
      minutes > 0 -> "#{minutes}m #{seconds}s"
      true -> "#{seconds}s"
    end
  end

  def run_status_badge(status) do
    case status do
      "pending" -> "bg-yellow-500/15 text-yellow-300 border-yellow-500/30"
      "running" -> "bg-blue-500/15 text-blue-300 border-blue-500/30"
      "completed" -> "bg-emerald-500/15 text-emerald-300 border-emerald-500/30"
      "failed" -> "bg-red-500/15 text-red-300 border-red-500/30"
      _ -> "bg-gray-500/15 text-gray-300 border-gray-500/30"
    end
  end

  # Distinguishes cron syncs, manual syncs, full imports, and dry-runs using
  # the metadata map written by the workers / Mix task.
  def run_type_badge(%{metadata: %{"run_type" => "import_dry_run"}}),
    do: {"Import (dry-run)", "bg-amber-500/15 text-amber-300 border-amber-500/30"}

  def run_type_badge(%{metadata: %{"run_type" => "import"}}),
    do: {"Import", "bg-purple-500/15 text-purple-300 border-purple-500/30"}

  def run_type_badge(%{metadata: %{"run_type" => "sync", "trigger" => "cron"}}),
    do: {"Sync (cron)", "bg-sky-500/15 text-sky-300 border-sky-500/30"}

  def run_type_badge(%{metadata: %{"run_type" => "sync"}}),
    do: {"Sync (manual)", "bg-teal-500/15 text-teal-300 border-teal-500/30"}

  def run_type_badge(_), do: {"Sync", "bg-teal-500/15 text-teal-300 border-teal-500/30"}

  def error_category_badge(category) do
    case category do
      "transient" -> "bg-yellow-500/15 text-yellow-300 border-yellow-500/30"
      "data" -> "bg-orange-500/15 text-orange-300 border-orange-500/30"
      "system" -> "bg-purple-500/15 text-purple-300 border-purple-500/30"
      "critical" -> "bg-red-500/15 text-red-300 border-red-500/30"
      _ -> "bg-gray-500/15 text-gray-300 border-gray-500/30"
    end
  end

  def stat_value(stats, key), do: Enum.sum(Enum.map(stats, &(&1[key] || 0)))

  def format_file_size(bytes) when bytes >= 1_048_576,
    do: ":.1f MB" |> :io_lib.format([bytes / 1_048_576]) |> to_string()

  def format_file_size(bytes) when bytes >= 1024,
    do: ":.1f KB" |> :io_lib.format([bytes / 1024]) |> to_string()

  def format_file_size(bytes), do: "#{bytes} B"

  # Stat card used at the top of the dashboard.
  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :icon, :string, required: true
  attr :tint, :string, required: true

  def sync_stat_card(assigns) do
    ~H"""
    <div class="kiroku-card p-5 flex items-center gap-4">
      <div
        class="w-10 h-10 rounded-lg flex items-center justify-center shrink-0"
        style={tint_bg(@tint)}
      >
        <span style={tint_fg(@tint)}>
          <.icon name={@icon} class="size-5" />
        </span>
      </div>
      <div class="min-w-0">
        <p class="font-heading text-2xl leading-none" style={tint_fg(@tint)}>
          {@value}
        </p>
        <p class="font-ui text-xs uppercase tracking-widest mt-1.5" style="color: var(--color-quill);">
          {@label}
        </p>
      </div>
    </div>
    """
  end

  defp tint_bg("patchouli"),
    do: "background: rgba(123,79,166,0.18);"

  defp tint_bg("emerald"), do: "background: rgba(16,185,129,0.15);"
  defp tint_bg("red"), do: "background: rgba(196,65,90,0.15);"
  defp tint_bg(_), do: "background: rgba(155,126,200,0.12);"

  defp tint_fg("patchouli"), do: "color: var(--color-patchouli);"
  defp tint_fg("emerald"), do: "color: #6ee7b7;"
  defp tint_fg("red"), do: "color: var(--color-ribbon-red);"
  defp tint_fg(_), do: "color: var(--color-lavender);"

  defp render_mssql_connection_status(%{assigns: assigns}) do
    status = assigns.mssql_connection_status

    case status.status do
      :connected ->
        ~H"""
        <div
          class="flex items-center gap-2 px-3 py-1.5 rounded-lg text-xs font-medium"
          style="background: rgba(16,185,129,0.15); color: #6ee7b7; border: 1px solid rgba(16,185,129,0.25);"
        >
          <.icon name="hero-check-circle" class="size-3.5" />
          <span>MSSQL Connected</span>
        </div>
        """

      :error ->
        ~H"""
        <div
          class="flex items-center gap-2 px-3 py-1.5 rounded-lg text-xs font-medium"
          style="background: rgba(196,65,90,0.15); color: var(--color-ribbon-red); border: 1px solid rgba(196,65,90,0.25);"
        >
          <.icon name="hero-x-circle" class="size-3.5" />
          <span>{@mssql_connection_status.message}</span>
        </div>
        """

      :not_configured ->
        ~H"""
        <div
          class="flex items-center gap-2 px-3 py-1.5 rounded-lg text-xs font-medium"
          style="background: rgba(251,146,60,0.15); color: #fb923c; border: 1px solid rgba(251,146,60,0.25);"
        >
          <.icon name="hero-exclamation-triangle" class="size-3.5" />
          <span>MSSQL Not Configured</span>
        </div>
        """
    end
  end

  defp render_connection_icon(%{assigns: assigns}) do
    connection_status = assigns.mssql_connection_status

    case connection_status.status do
      :connected ->
        ~H"""
        <span style="color: #6ee7b7;">
          <.icon name="hero-check-circle" class="size-5" />
        </span>
        """

      :error ->
        ~H"""
        <span style="color: var(--color-ribbon-red);">
          <.icon name="hero-x-circle" class="size-5" />
        </span>
        """

      :not_configured ->
        ~H"""
        <span style="color: #fb923c;">
          <.icon name="hero-exclamation-triangle" class="size-5" />
        </span>
        """
    end
  end

  defp render_connection_details(%{assigns: assigns}) do
    connection_status = assigns.mssql_connection_status

    if connection_status.status == :connected do
      ~H"""
      <div class="mt-3 p-3 rounded-lg text-xs space-y-1" style="background: rgba(16,185,129,0.08);">
        <div class="flex justify-between">
          <span style="color: var(--color-quill);">Server Version:</span>
          <span style="color: var(--color-lilac);">{@mssql_connection_status.version}</span>
        </div>
      </div>
      """
    else
      ~H"""
      """
    end
  end
end
