defmodule KirokuWeb.AdminSafLive do
  @moduledoc """
  Dedicated dashboard for DSpace Simple Archive Format (SAF) import/export.

  Mounted at `/admin/saf`. Restricted to admins and superadmins.

  Import: uploaded zip archives are staged in the OS temp directory (`/tmp`)
  — never S3 — and cleaned up after processing. Individual bitstreams within
  the archive are stored via the configured storage adapter (local or S3).

  Export: produces downloadable zip archives per collection, stored in
  `priv/saf_exports/`.
  """

  use KirokuWeb, :live_view

  alias Kiroku.{Repo, Saf}
  alias Kiroku.Workers.{SafExportWorker, SafImportWorker}
  import Ecto.Query

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_user} page_title="SAF Import &amp; Export">
      <div class="space-y-8">
        <%!-- Header ──────────────────────────────────────────────────────── --%>
        <div>
          <h1 class="font-heading text-3xl" style="color: var(--color-lilac);">
            SAF Import &amp; Export
          </h1>
          <p class="font-body text-sm mt-1" style="color: var(--color-quill);">
            Import and export items using the DSpace Simple Archive Format. Upload zips are processed from the local filesystem and cleaned up after.
          </p>
        </div>

        <div class="grid lg:grid-cols-2 gap-6">
          <%!-- SAF Export ─────────────────────────────────────────────── --%>
          <div class="kiroku-card p-6 space-y-4">
            <div class="flex items-center gap-2">
              <span style="color: var(--color-patchouli);">
                <.icon name="hero-arrow-up-tray" class="size-5" />
              </span>
              <h2 class="font-heading text-lg" style="color: var(--color-lilac);">
                Export
              </h2>
            </div>
            <p class="text-xs" style="color: var(--color-quill);">
              Export a collection to a downloadable DSpace SAF zip (metadata + files).
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
                Import
              </h2>
            </div>
            <p class="text-xs" style="color: var(--color-quill);">
              Upload a SAF zip. Items are upserted by handle (re-importing updates existing items).
            </p>

            <form phx-submit="saf_import" phx-change="saf_validate" class="space-y-3">
              <.live_file_input upload={@uploads.saf_archive} class="hidden" />

              <%!-- Upload drop zone ────────────────────────────────────── --%>
              <div
                phx-drop-target={@uploads.saf_archive.ref}
                class={[
                  "relative rounded-xl border-2 border-dashed transition-all cursor-pointer",
                  if(@uploads.saf_archive.entries == [],
                    do: "p-8 text-center hover:border-purple-400/60",
                    else: "p-4 border-transparent"
                  )
                ]}
                style="border-color: rgba(155,126,200,0.25); background: rgba(155,126,200,0.04);"
              >
                <label
                  for={@uploads.saf_archive.ref}
                  class="block cursor-pointer"
                >
                  <%= if @uploads.saf_archive.entries == [] do %>
                    <div class="flex flex-col items-center gap-2">
                      <.icon
                        name="hero-cloud-arrow-up"
                        class="size-8"
                        style="color: var(--color-wisteria); opacity: 0.6;"
                      />
                      <p class="text-sm font-medium" style="color: var(--color-wisteria);">
                        Click to browse or drag a SAF zip here
                      </p>
                      <p class="text-xs" style="color: var(--color-quill);">
                        .zip format, up to 500 MB
                      </p>
                    </div>
                  <% end %>
                </label>

                <%!-- Upload errors ─────────────────────────────────────── --%>
                <div
                  :for={err <- upload_errors(@uploads.saf_archive)}
                  class="mt-2 text-xs text-center"
                  style="color: var(--color-ribbon-red);"
                >
                  {error_to_string(err)}
                </div>

                <%!-- Selected file entries ─────────────────────────────── --%>
                <div
                  :for={entry <- @uploads.saf_archive.entries}
                  class="flex items-center justify-between px-3 py-2 rounded-lg"
                  style="background: rgba(155,126,200,0.08);"
                >
                  <div class="flex items-center gap-2.5 min-w-0">
                    <.icon
                      name="hero-document-text"
                      class="size-4 shrink-0"
                      style="color: var(--color-patchouli);"
                    />
                    <div class="min-w-0">
                      <p class="text-sm truncate" style="color: var(--color-lilac);">
                        {entry.client_name}
                      </p>
                      <p class="text-xs" style="color: var(--color-quill);">
                        {format_file_size(entry.client_size)}
                      </p>
                    </div>
                  </div>
                  <button
                    type="button"
                    phx-click="saf_cancel_upload"
                    phx-value-ref={entry.ref}
                    class="shrink-0 p-1 rounded-lg transition-colors hover:bg-base-300/50"
                    style="color: var(--color-quill);"
                    aria-label="Remove file"
                  >
                    <.icon name="hero-x-mark" class="size-4" />
                  </button>
                </div>
              </div>

              <%!-- Collection override ─────────────────────────────────── --%>
              <div>
                <label
                  class="block text-xs uppercase tracking-wider mb-1.5"
                  style="color: var(--color-quill);"
                >
                  Override collection (optional)
                </label>
                <select
                  name="collection"
                  class="kiroku-search-input w-full"
                  phx-change="saf_select_collection"
                >
                  <option value="">Use collection from archive</option>
                  <option
                    :for={{name, handle} <- @collections}
                    value={handle}
                    selected={handle == @saf_collection}
                  >
                    {name}
                  </option>
                </select>
              </div>

              <%!-- Dry-run checkbox ────────────────────────────────────── --%>
              <label class="flex items-center gap-2.5 cursor-pointer select-none">
                <input
                  type="checkbox"
                  phx-click="saf_toggle_dry_run"
                  phx-value-dry_run={!@saf_dry_run}
                  checked={@saf_dry_run}
                  class="h-4 w-4 rounded"
                  style="accent-color: var(--color-patchouli);"
                />
                <span class="text-sm" style="color: var(--color-wisteria);">
                  Dry run (validate only — no writes)
                </span>
              </label>

              <button
                type="submit"
                disabled={@uploads.saf_archive.entries == []}
                class={[
                  "w-full px-3 py-2 rounded-lg text-sm font-semibold transition-all hover:brightness-110 active:scale-95 disabled:opacity-40 disabled:cursor-not-allowed",
                  if(@saf_dry_run,
                    do: "bg-amber-500 text-white",
                    else: "text-white"
                  )
                ]}
                style={if not @saf_dry_run, do: "background: var(--color-patchouli);", else: nil}
              >
                {if(@saf_dry_run, do: "Dry-run import", else: "Import archive")}
              </button>
            </form>
          </div>
        </div>

        <%!-- Exported archives (download links) ─────────────────────────── --%>
        <div :if={@saf_exports != []} class="kiroku-card overflow-hidden">
          <div
            class="p-5 flex items-center justify-between"
            style="border-bottom: 1px solid rgba(155,126,200,0.12);"
          >
            <div class="flex items-center gap-2">
              <.icon name="hero-archive-box" class="size-5" style="color: var(--color-patchouli);" />
              <h2 class="font-heading text-base" style="color: var(--color-wisteria);">
                Exported Archives
              </h2>
            </div>
            <span class="text-xs" style="color: var(--color-quill);">
              {@saf_exports |> length()} file(s) — cleaned up after 24h
            </span>
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
      </div>
    </Layouts.admin>
    """
  end

  # ── Lifecycle ──────────────────────────────────────────────────────────────

  @impl true
  def mount(_params, _session, socket) do
    if staff?(socket) do
      {:ok,
       socket
       |> allow_upload(:saf_archive,
         accept: ~w(.zip),
         max_entries: 1,
         max_file_size: 500_000_000,
         auto_upload: false
       )
       |> assign(:saf_collection, "")
       |> assign(:saf_dry_run, false)
       |> assign_saf_data()}
    else
      {:ok,
       socket
       |> put_flash(:error, "Only staff may access this page.")
       |> push_navigate(to: ~p"/admin")}
    end
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  # ── Events ─────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("saf_validate", _params, socket), do: {:noreply, socket}

  def handle_event("saf_select_collection", %{"collection" => handle}, socket) do
    {:noreply, assign(socket, :saf_collection, handle)}
  end

  def handle_event("saf_toggle_dry_run", %{"dry_run" => dry?}, socket) do
    {:noreply, assign(socket, :saf_dry_run, dry? == "true")}
  end

  def handle_event("saf_cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :saf_archive, ref)}
  end

  def handle_event("saf_export", %{"collection" => collection_handle, "scope" => scope}, socket) do
    args = %{
      "target" => "collection",
      "id" => collection_handle,
      "only" => scope,
      "triggered_by" => triggered_by(socket)
    }

    enqueue_job(
      SafExportWorker,
      args,
      socket,
      "SAF export queued — the zip will appear below when ready."
    )
  end

  def handle_event("saf_import", _params, socket) do
    case consume_uploaded_entries(socket, :saf_archive, fn %{path: path}, _entry ->
           # Stage the uploaded zip in the OS temp directory (NOT S3, NOT
           # priv/saf_imports). The worker deletes it after processing.
           dest = Path.join(System.tmp_dir!(), "kiroku_saf_import_#{Ecto.UUID.generate()}.zip")
           File.cp!(path, dest)
           {:ok, dest}
         end) do
      [source] ->
        args = %{
          "source" => source,
          "dry_run" => socket.assigns.saf_dry_run,
          "triggered_by" => triggered_by(socket)
        }

        args =
          if socket.assigns.saf_collection != "",
            do: Map.put(args, "collection", socket.assigns.saf_collection),
            else: args

        enqueue_job(
          SafImportWorker,
          args,
          socket,
          if(socket.assigns.saf_dry_run,
            do: "Dry-run import queued (nothing will be written).",
            else: "SAF import queued — check the table below for results."
          )
        )

      [] ->
        {:noreply, put_flash(socket, :error, "Choose a SAF zip file first.")}
    end
  end

  def handle_event("refresh", _, socket) do
    {:noreply, assign_saf_data(socket)}
  end

  # ── Data loading ───────────────────────────────────────────────────────────

  defp assign_saf_data(socket) do
    assign(socket, %{
      collections:
        Repo.all(
          from c in Kiroku.Repository.Collection, order_by: c.name, select: {c.name, c.handle}
        ),
      saf_exports: Saf.list_exports()
    })
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
         |> assign_saf_data()}

      {:error, _changeset} ->
        {:noreply,
         put_flash(socket, :error, "Could not queue the job. It may already be running.")}
    end
  end

  # ── Render helpers ─────────────────────────────────────────────────────────

  def format_file_size(bytes) when bytes >= 1_048_576,
    do: ":.1f MB" |> :io_lib.format([bytes / 1_048_576]) |> to_string()

  def format_file_size(bytes) when bytes >= 1024,
    do: ":.1f KB" |> :io_lib.format([bytes / 1024]) |> to_string()

  def format_file_size(bytes), do: "#{bytes} B"

  defp error_to_string(:too_large), do: "File exceeds the 500 MB limit."
  defp error_to_string(:not_accepted), do: "Only .zip files are accepted."
  defp error_to_string(:too_many_files), do: "Only one file at a time."
  defp error_to_string(_), do: "Upload error."
end
