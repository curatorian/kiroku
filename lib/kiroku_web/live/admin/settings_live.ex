defmodule KirokuWeb.Admin.SettingsLive do
  use KirokuWeb, :live_view

  alias Kiroku.Settings
  alias Kiroku.Storage.Uploader

  @impl true
  def mount(_params, _session, socket) do
    storage = Settings.storage_settings()
    brand = Settings.brand_settings()

    embargo = Settings.embargo_settings()
    mailer = Settings.mailer_settings()
    allow_submit = Settings.allow_user_submit?()
    allow_reg = Settings.allow_registration?()
    locked_descs = Settings.locked_bitstream_descriptions()
    file_lock_mode = Settings.file_lock_mode()

    socket =
      socket
      |> assign(:page_title, "System Settings")
      |> assign(:storage_adapter, storage.adapter)
      |> assign(:storage_form, to_form(storage_form_params(storage), as: :storage))
      |> assign(:brand_form, to_form(brand_form_params(brand), as: :brand))
      |> assign(:embargo_form, to_form(embargo_form_params(embargo), as: :embargo))
      |> assign(:mailer_adapter, mailer.provider)
      |> assign(:mailer_form, to_form(mailer_form_params(mailer), as: :mailer))
      |> assign(:allow_submit, allow_submit)
      |> assign(:allow_registration, allow_reg)
      |> assign(:locked_descriptions, locked_descs)
      |> assign(:file_lock_mode, file_lock_mode)
      |> assign(:brand_logo_url, Settings.brand_logo_url())
      |> allow_upload(:logo,
        accept: ~w(.png .jpg .jpeg .svg .ico .webp),
        max_entries: 1,
        max_file_size: 2_000_000
      )

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_user} page_title="Settings">
      <div class="max-w-2xl mx-auto px-4 py-8 space-y-8">
        <div>
          <h1 class="font-heading text-3xl" style="color: var(--color-lilac);">System Settings</h1>
          <p class="text-sm mt-1" style="color: var(--color-quill);">
            Configure storage and other runtime options. Changes take effect immediately.
            Environment variables are used as fallback when a setting is not saved here.
          </p>
        </div>

        <%!-- Storage settings --%>
        <div id="storage-settings" class="kiroku-card p-6 space-y-5">
          <h2 class="font-heading text-lg" style="color: var(--color-wisteria);">
            File Storage
          </h2>

          <.form
            for={@storage_form}
            id="storage-form"
            phx-submit="save_storage"
            phx-change="storage_changed"
            class="space-y-5"
          >
            <div>
              <label
                class="block text-sm font-medium mb-1.5"
                style="color: var(--color-wisteria);"
              >
                Storage Adapter
              </label>
              <select
                name="storage[adapter]"
                id="storage-adapter-select"
                class="kiroku-search-input w-full"
              >
                <option value="local" selected={@storage_adapter == :local}>
                  Local Disk (priv/uploads/)
                </option>
                <option value="s3" selected={@storage_adapter == :s3}>
                  S3 / S3-Compatible (AWS, MinIO, Cloudflare R2, etc.)
                </option>
              </select>
              <p class="text-xs mt-1" style="color: var(--color-quill);">
                Env var: <code>STORAGE_ADAPTER=local|s3</code>
              </p>
            </div>

            <%= if @storage_adapter == :s3 do %>
              <div
                id="s3-fields"
                class="space-y-4 pt-2 border-t"
                style="border-color: rgba(155,126,200,0.15);"
              >
                <p class="text-xs" style="color: var(--color-quill);">
                  Leave fields blank to use environment variables
                  (S3_ACCESS_KEY_ID, S3_SECRET_ACCESS_KEY, S3_REGION, S3_BUCKET, S3_ENDPOINT, S3_PUBLIC_URL).
                </p>

                <.input
                  field={@storage_form[:bucket]}
                  type="text"
                  label="S3 Bucket Name"
                  placeholder="kiroku-uploads (or $S3_BUCKET)"
                />

                <.input
                  field={@storage_form[:region]}
                  type="text"
                  label="AWS Region"
                  placeholder="ap-southeast-1 (or $S3_REGION)"
                />

                <.input
                  field={@storage_form[:endpoint]}
                  type="text"
                  label="Custom Endpoint URL (API)"
                  placeholder="https://minio.domain.com (S3 API — for MinIO, R2, etc.)"
                />

                <.input
                  field={@storage_form[:public_url]}
                  type="text"
                  label="Public Base URL (override)"
                  placeholder="https://cdn.example.com/bucket-name"
                />
                <p class="text-xs -mt-2" style="color: var(--color-quill);">
                  Optional. When left blank and a Custom Endpoint is set (MinIO, R2, etc.),
                  public file links are built automatically as <code>endpoint/bucket/key</code>.
                  Set this only when your public CDN domain differs from the API endpoint.
                </p>

                <.input
                  field={@storage_form[:access_key_id]}
                  type="text"
                  label="Access Key ID"
                  placeholder="(leave blank to use $S3_ACCESS_KEY_ID)"
                />

                <.input
                  field={@storage_form[:secret_access_key]}
                  type="password"
                  label="Secret Access Key"
                  placeholder="(leave blank to use $S3_SECRET_ACCESS_KEY)"
                />
              </div>
            <% end %>

            <div class="pt-2">
              <button
                type="submit"
                class="inline-flex items-center gap-2 px-5 py-2.5 rounded-lg font-semibold text-sm transition-all duration-150 hover:brightness-110 active:scale-95"
                style="background: var(--color-patchouli); color: white; box-shadow: 0 2px 8px rgba(123,79,166,0.35);"
              >
                <.icon name="hero-arrow-down-tray" class="size-4" /> Save Storage Settings
              </button>
            </div>
          </.form>

          <%!-- Current effective settings --%>
          <div class="pt-4 border-t" style="border-color: rgba(155,126,200,0.15);">
            <p class="text-xs font-medium mb-2" style="color: var(--color-wisteria);">
              Effective settings (DB overrides env vars):
            </p>
            <dl class="space-y-1 text-xs" style="color: var(--color-quill);">
              <div class="flex gap-2">
                <dt class="font-medium w-32 shrink-0">Adapter:</dt>
                <dd><code>{Settings.storage_adapter()}</code></dd>
              </div>
              <div class="flex gap-2">
                <dt class="font-medium w-32 shrink-0">Bucket:</dt>
                <dd><code>{Settings.storage_bucket()}</code></dd>
              </div>
              <div class="flex gap-2">
                <dt class="font-medium w-32 shrink-0">Region:</dt>
                <dd><code>{Settings.storage_region()}</code></dd>
              </div>
              <%= if Settings.storage_endpoint() do %>
                <div class="flex gap-2">
                  <dt class="font-medium w-32 shrink-0">Endpoint:</dt>
                  <dd><code>{Settings.storage_endpoint()}</code></dd>
                </div>
              <% end %>
              <%= if Settings.storage_public_url() do %>
                <div class="flex gap-2">
                  <dt class="font-medium w-32 shrink-0">Public URL:</dt>
                  <dd><code>{Settings.storage_public_url()}</code></dd>
                </div>
              <% end %>
            </dl>
          </div>
        </div>

        <%!-- Brand settings --%>
        <div id="brand-settings" class="kiroku-card p-6 space-y-5">
          <div>
            <h2 class="font-heading text-lg" style="color: var(--color-wisteria);">
              Brand & Identity
            </h2>
            <p class="text-xs mt-1" style="color: var(--color-quill);">
              Customise the repository's name, tagline, contact details, and visual identity.
            </p>
          </div>

          <.form
            for={@brand_form}
            id="brand-form"
            phx-submit="save_brand"
            class="space-y-5"
          >
            <.input
              field={@brand_form[:name]}
              type="text"
              label="Brand Name"
              placeholder="Kiroku"
            />

            <.input
              field={@brand_form[:tagline]}
              type="text"
              label="Tagline"
              placeholder="Every work recorded. Every scholar remembered."
            />

            <.input
              field={@brand_form[:description]}
              type="textarea"
              label="Description"
              placeholder="The institutional repository for scholarly works…"
              rows={3}
            />

            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <.input
                field={@brand_form[:contact_email]}
                type="email"
                label="Contact E-Mail"
                placeholder="curatorian@proton.me"
              />
              <.input
                field={@brand_form[:contact_phone]}
                type="text"
                label="Contact Phone"
                placeholder="08123456789"
              />
            </div>

            <.input
              field={@brand_form[:handle_prefix]}
              type="text"
              label="Handle Prefix"
              placeholder="kandaga"
            />
            <p class="text-xs" style="color: var(--color-quill);">
              Used for DSpace-style handles (e.g. <code>kandaga/12345</code>). Default: <code>kandaga</code>.
              Affects newly imported items and communities.
            </p>

            <%!-- Brand colour picker --%>
            <div>
              <label
                class="block text-sm font-medium mb-1.5"
                style="color: var(--color-wisteria);"
              >
                Primary Brand Colour
              </label>
              <div class="flex items-center gap-3">
                <input
                  type="color"
                  id="brand-color-picker"
                  name="brand[primary_color]"
                  value={Phoenix.HTML.Form.input_value(@brand_form, :primary_color)}
                  class="h-10 w-16 rounded-lg border cursor-pointer"
                  style="border-color: rgba(155,126,200,0.3); background: var(--color-grimoire); padding: 2px 4px;"
                />
                <input
                  type="text"
                  id="brand-color-text"
                  name="brand[primary_color_text]"
                  value={Phoenix.HTML.Form.input_value(@brand_form, :primary_color)}
                  placeholder="#7B4FA6"
                  class="kiroku-search-input w-32 font-mono text-sm"
                  phx-hook=".ColorSync"
                />
              </div>
              <p class="text-xs mt-1" style="color: var(--color-quill);">
                Default: <code>#7B4FA6</code>
                (Patchouli violet). Overrides the primary colour across the entire site.
              </p>
            </div>

            <div class="pt-2">
              <button
                type="submit"
                class="inline-flex items-center gap-2 px-5 py-2.5 rounded-lg font-semibold text-sm transition-all duration-150 hover:brightness-110 active:scale-95"
                style="background: var(--color-patchouli); color: white; box-shadow: 0 2px 8px rgba(123,79,166,0.35);"
              >
                <.icon name="hero-arrow-down-tray" class="size-4" /> Save Brand Settings
              </button>
            </div>
          </.form>

          <%!-- Logo upload — managed separately from the brand text form --%>
          <div
            id="logo-upload"
            class="space-y-3 pt-2 border-t"
            style="border-color: rgba(155,126,200,0.15);"
          >
            <div>
              <label class="block text-sm font-medium mb-1" style="color: var(--color-wisteria);">
                Logo
              </label>
              <p class="text-xs" style="color: var(--color-quill);">
                Upload a logo (PNG/JPG/SVG/ICO/WebP, maks. 2&nbsp;MB). Used as the site logo and the
                browser favicon. Leave unset to fall back to the default <code>kiroku.ico</code>.
              </p>
            </div>

            <%= if @brand_logo_url do %>
              <div
                class="flex items-center gap-3 rounded-xl p-3"
                style="background: color-mix(in srgb, var(--color-patchouli) 7%, transparent); border: 1px solid color-mix(in srgb, var(--color-lavender) 14%, transparent);"
              >
                <span
                  class="w-12 h-12 rounded-lg flex items-center justify-center shrink-0 overflow-hidden"
                  style="background: white;"
                >
                  <img src={@brand_logo_url} alt="Logo" class="max-h-10 max-w-full object-contain" />
                </span>
                <span
                  class="text-xs truncate flex-1 min-w-0 font-mono"
                  style="color: var(--color-quill);"
                  title={@brand_logo_url}
                >
                  {@brand_logo_url}
                </span>
                <button
                  type="button"
                  phx-click="remove_logo"
                  data-confirm="Remove the current logo and fall back to the default?"
                  class="text-xs px-3 py-1.5 rounded-lg transition-colors hover:bg-white/5"
                  style="color: var(--color-quill);"
                >
                  <.icon name="hero-trash" class="w-4 h-4 inline -mt-0.5" /> Remove
                </button>
              </div>
            <% end %>

            <%!-- Uploads are most reliable (and testable) inside a form; the
                 phx-submit consumes the staged file and stores the logo. --%>
            <form id="logo-form" phx-submit="upload_logo" phx-change="validate_logo" class="block">
              <div
                class="upload-dropzone group relative flex flex-col items-center justify-center gap-2 px-6 py-6 rounded-2xl border-2 border-dashed cursor-pointer transition-all duration-200"
                phx-drop-target={@uploads.logo.ref}
              >
                <.live_file_input
                  upload={@uploads.logo}
                  class="absolute inset-0 w-full h-full opacity-0 cursor-pointer"
                />
                <div class="flex flex-col items-center gap-1.5 text-center pointer-events-none">
                  <span
                    class="w-10 h-10 rounded-xl flex items-center justify-center transition-transform duration-200 group-hover:scale-110"
                    style="background: color-mix(in srgb, var(--color-patchouli) 16%, transparent); color: var(--color-lavender);"
                  >
                    <.icon name="hero-photo" class="w-5 h-5" />
                  </span>
                  <p class="text-sm font-medium" style="color: var(--color-wisteria);">
                    Pilih atau seret logo ke sini
                  </p>
                  <p class="text-xs" style="color: var(--color-quill);">
                    Klik untuk memilih berkas
                  </p>
                </div>
              </div>

              <%= for entry <- @uploads.logo.entries do %>
                <div
                  class="flex items-center gap-2 text-xs rounded-lg px-3 py-2"
                  style="background: color-mix(in srgb, var(--color-patchouli) 7%, transparent); color: var(--color-wisteria);"
                >
                  <.icon name="hero-document" class="w-4 h-4 shrink-0" />
                  <span class="flex-1 truncate">{entry.client_name}</span>
                  <span style="color: var(--color-quill);">
                    {Float.round(entry.client_size / 1_000_000, 2)} MB
                  </span>
                  <button
                    type="button"
                    phx-click="cancel_logo_upload"
                    phx-value-ref={entry.ref}
                    class="hover:opacity-70 transition-opacity"
                  >
                    <.icon name="hero-x-mark" class="w-4 h-4" />
                  </button>
                </div>
                <%= for err <- upload_errors(@uploads.logo, entry) do %>
                  <p class="text-xs" style="color: var(--color-ribbon-red);">
                    {upload_error_to_string(err)}
                  </p>
                <% end %>
              <% end %>
              <%= for err <- upload_errors(@uploads.logo) do %>
                <p class="text-xs" style="color: var(--color-ribbon-red);">
                  {upload_error_to_string(err)}
                </p>
              <% end %>

              <div :if={@uploads.logo.entries != []} class="pt-1">
                <button
                  type="submit"
                  class="inline-flex items-center gap-2 px-5 py-2 rounded-lg font-semibold text-sm transition-all duration-150 hover:brightness-110 active:scale-95"
                  style="background: var(--color-patchouli); color: white; box-shadow: 0 2px 8px rgba(123,79,166,0.35);"
                >
                  <.icon name="hero-arrow-up-tray" class="size-4" /> Upload Logo
                </button>
              </div>
            </form>
          </div>
        </div>

        <%!-- Embargo scheduler settings --%>
        <div id="embargo-settings" class="kiroku-card p-6 space-y-5">
          <div>
            <h2 class="font-heading text-lg" style="color: var(--color-wisteria);">
              Embargo Scheduler
            </h2>
            <p class="text-xs mt-1" style="color: var(--color-quill);">
              Configure the cron schedule for automatic embargo lifting.
              Changes take effect on the next application restart.
            </p>
          </div>

          <.form
            for={@embargo_form}
            id="embargo-form"
            phx-submit="save_embargo"
            class="space-y-5"
          >
            <.input
              field={@embargo_form[:cron_schedule]}
              type="text"
              label="Cron Schedule"
              placeholder="0 2 * * *"
            />
            <p class="text-xs" style="color: var(--color-quill);">
              Standard 5-field cron format. Default <code>0 2 * * *</code>
              runs daily at 02:00. Env var: <code>EMBARGO_CRON</code>.
            </p>

            <div class="flex items-center gap-3 pt-2">
              <button
                type="submit"
                class="inline-flex items-center gap-2 px-5 py-2.5 rounded-lg font-semibold text-sm transition-all duration-150 hover:brightness-110 active:scale-95"
                style="background: var(--color-patchouli); color: white; box-shadow: 0 2px 8px rgba(123,79,166,0.35);"
              >
                <.icon name="hero-arrow-down-tray" class="size-4" /> Save Schedule
              </button>

              <button
                type="button"
                phx-click="run_embargo_lifter"
                class="inline-flex items-center gap-2 px-4 py-2.5 rounded-lg font-semibold text-sm transition-all duration-150 hover:brightness-110 active:scale-95"
                style="background: transparent; color: var(--color-lavender); border: 1px solid rgba(155,126,200,0.4);"
              >
                <.icon name="hero-play" class="size-4" /> Run Now
              </button>
            </div>
          </.form>
        </div>

        <%!-- Submission toggle --%>
        <div id="submission-settings" class="kiroku-card p-6 space-y-5">
          <div>
            <h2 class="font-heading text-lg" style="color: var(--color-wisteria);">
              Users & Access
            </h2>
            <p class="text-xs mt-1" style="color: var(--color-quill);">
              Control self-registration and item submission. PAuS login always works regardless of these settings.
            </p>
          </div>

          <.form for={nil} id="submission-form" phx-submit="save_submission" class="space-y-4">
            <label class="flex items-center gap-3 cursor-pointer">
              <input
                type="checkbox"
                name="submission[allow_registration]"
                value="true"
                checked={@allow_registration}
                class="h-5 w-5 rounded"
                style="accent-color: var(--color-patchouli);"
              />
              <span class="text-sm" style="color: var(--color-wisteria);">
                Allow self-registration (email/password)
              </span>
            </label>

            <label class="flex items-center gap-3 cursor-pointer">
              <input
                type="checkbox"
                name="submission[allow_user_submit]"
                value="true"
                checked={@allow_submit}
                class="h-5 w-5 rounded"
                style="accent-color: var(--color-patchouli);"
              />
              <span class="text-sm" style="color: var(--color-wisteria);">
                Allow users to submit items
              </span>
            </label>

            <div class="pt-1">
              <button
                type="submit"
                class="inline-flex items-center gap-2 px-5 py-2.5 rounded-lg font-semibold text-sm transition-all duration-150 hover:brightness-110 active:scale-95"
                style="background: var(--color-patchouli); color: white; box-shadow: 0 2px 8px rgba(123,79,166,0.35);"
              >
                <.icon name="hero-arrow-down-tray" class="size-4" /> Save
              </button>
            </div>
          </.form>
        </div>

        <%!-- File Access Control --%>
        <div id="file-access-settings" class="kiroku-card p-6 space-y-5">
          <div>
            <h2 class="font-heading text-lg" style="color: var(--color-wisteria);">
              File Access Control
            </h2>
            <p class="text-xs mt-1" style="color: var(--color-quill);">
              Toggle which file types are locked from public view, then choose
              a lock mode. Applies globally to all items.
            </p>
          </div>

          <.form for={nil} id="file-access-form" phx-submit="save_file_locks" class="space-y-4">
            <%!-- Lock Mode --%>
            <div class="space-y-2">
              <span
                class="text-xs font-semibold uppercase tracking-wide"
                style="color: var(--color-quill);"
              >
                Lock Mode
              </span>
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-2">
                <label
                  class={[
                    "flex items-start gap-2.5 p-3 rounded-lg cursor-pointer text-sm transition-all",
                    if(@file_lock_mode == :internal,
                      do: "ring-2 ring-offset-1",
                      else: "hover:brightness-105"
                    )
                  ]}
                  style={
                    if @file_lock_mode == :internal,
                      do:
                        "background: rgba(123,79,166,0.12); border: 1px solid var(--color-patchouli); ring-color: var(--color-patchouli);",
                      else:
                        "background: rgba(155,126,200,0.06); border: 1px solid rgba(155,126,200,0.15);"
                  }
                >
                  <input
                    type="radio"
                    name="mode"
                    value="internal"
                    checked={@file_lock_mode == :internal}
                    class="mt-0.5 h-4 w-4"
                    style="accent-color: var(--color-patchouli);"
                  />
                  <span>
                    <span class="font-medium block" style="color: var(--color-wisteria);">
                      Internal unlock
                    </span>
                    <span class="text-[11px] block mt-0.5" style="color: var(--color-quill);">
                      Visible to <strong>internal</strong> users (students/lecturers) and staff.
                    </span>
                  </span>
                </label>

                <label
                  class={[
                    "flex items-start gap-2.5 p-3 rounded-lg cursor-pointer text-sm transition-all",
                    if(@file_lock_mode == :closed,
                      do: "ring-2 ring-offset-1",
                      else: "hover:brightness-105"
                    )
                  ]}
                  style={
                    if @file_lock_mode == :closed,
                      do:
                        "background: rgba(196,65,90,0.12); border: 1px solid var(--color-ribbon-red); ring-color: var(--color-ribbon-red);",
                      else:
                        "background: rgba(155,126,200,0.06); border: 1px solid rgba(155,126,200,0.15);"
                  }
                >
                  <input
                    type="radio"
                    name="mode"
                    value="closed"
                    checked={@file_lock_mode == :closed}
                    class="mt-0.5 h-4 w-4"
                    style="accent-color: var(--color-ribbon-red);"
                  />
                  <span>
                    <span class="font-medium block" style="color: var(--color-ribbon-red);">
                      Fully closed
                    </span>
                    <span class="text-[11px] block mt-0.5" style="color: var(--color-quill);">
                      Visible <strong>only</strong> to superadmin. All other roles are denied.
                    </span>
                  </span>
                </label>
              </div>
            </div>

            <div class="space-y-2">
              <span
                class="text-xs font-semibold uppercase tracking-wide"
                style="color: var(--color-quill);"
              >
                Locked File Types
              </span>
              <div class="grid grid-cols-2 sm:grid-cols-3 gap-2">
                <%= for desc <- ["Bab 1", "Bab 2", "Bab 3", "Bab 4", "Bab 5", "Bab 6", "Abstract", "Daftar isi", "Daftar pustaka", "Lampiran", "Lembar pengesahan", "Surat pengantar", "Full text"] do %>
                  <% checked = desc in @locked_descriptions %>
                  <label
                    class={[
                      "flex items-center gap-2 p-2.5 rounded-lg cursor-pointer text-sm transition-colors",
                      if checked do
                        "text-white"
                      else
                        ""
                      end
                    ]}
                    style={
                      if checked,
                        do:
                          "background: rgba(196,65,90,0.15); border: 1px solid rgba(196,65,90,0.3);",
                        else:
                          "background: rgba(155,126,200,0.08); border: 1px solid rgba(155,126,200,0.15);"
                    }
                  >
                    <input
                      type="checkbox"
                      name="locked[]"
                      value={desc}
                      checked={checked}
                      class="h-4 w-4 rounded"
                      style="accent-color: var(--color-ribbon-red);"
                    />
                    <span style={
                      if checked,
                        do: "color: var(--color-ribbon-red);",
                        else: "color: var(--color-wisteria);"
                    }>
                      {desc}
                    </span>
                  </label>
                <% end %>
              </div>
            </div>

            <div class="pt-1">
              <button
                type="submit"
                class="inline-flex items-center gap-2 px-5 py-2.5 rounded-lg font-semibold text-sm transition-all duration-150 hover:brightness-110 active:scale-95"
                style="background: var(--color-patchouli); color: white; box-shadow: 0 2px 8px rgba(123,79,166,0.35);"
              >
                <.icon name="hero-arrow-down-tray" class="size-4" /> Save Locks
              </button>
            </div>
          </.form>
        </div>

        <%!-- Mailer settings --%>
        <div id="mailer-settings" class="kiroku-card p-6 space-y-5">
          <div>
            <h2 class="font-heading text-lg" style="color: var(--color-wisteria);">
              Email (Mailer)
            </h2>
            <p class="text-xs mt-1" style="color: var(--color-quill);">
              Used for review notifications and password resets. Changes take effect immediately.
              Fields left blank fall back to environment variables.
            </p>
          </div>

          <.form
            for={@mailer_form}
            id="mailer-form"
            phx-submit="save_mailer"
            phx-change="mailer_changed"
            class="space-y-5"
          >
            <div>
              <label class="block text-sm font-medium mb-1.5" style="color: var(--color-wisteria);">
                Email provider
              </label>
              <select name="mailer[provider]" class="kiroku-search-input w-full">
                <option value="local" selected={@mailer_adapter == "local"}>
                  Local (no sending — dev / staging)
                </option>
                <option value="smtp" selected={@mailer_adapter == "smtp"}>
                  SMTP server
                </option>
              </select>
            </div>

            <.input
              field={@mailer_form[:from]}
              type="email"
              label="From address"
              placeholder="noreply@university.ac.id"
            />

            <%= if @mailer_adapter == "smtp" do %>
              <div
                id="smtp-fields"
                class="space-y-4 pt-2 border-t"
                style="border-color: rgba(155,126,200,0.15);"
              >
                <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
                  <div class="sm:col-span-2">
                    <.input
                      field={@mailer_form[:host]}
                      type="text"
                      label="SMTP host"
                      placeholder="smtp.gmail.com"
                    />
                  </div>
                  <.input field={@mailer_form[:port]} type="number" label="Port" placeholder="587" />
                </div>

                <.input
                  field={@mailer_form[:username]}
                  type="text"
                  label="SMTP username"
                  placeholder="(leave blank to use env vars)"
                />

                <.input
                  field={@mailer_form[:password]}
                  type="password"
                  label="SMTP password"
                  placeholder="(leave blank to keep existing)"
                />
              </div>
            <% end %>

            <div class="pt-2">
              <button
                type="submit"
                class="inline-flex items-center gap-2 px-5 py-2.5 rounded-lg font-semibold text-sm transition-all duration-150 hover:brightness-110 active:scale-95"
                style="background: var(--color-patchouli); color: white; box-shadow: 0 2px 8px rgba(123,79,166,0.35);"
              >
                <.icon name="hero-arrow-down-tray" class="size-4" /> Save Mailer Settings
              </button>
            </div>
          </.form>
        </div>
      </div>
    </Layouts.admin>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".ColorSync">
      export default {
        mounted() {
          const picker = document.getElementById("brand-color-picker")
          const text   = this.el

          // Sync picker → text
          picker.addEventListener("input", () => { text.value = picker.value })
          // Sync text → picker (on valid hex)
          text.addEventListener("input", () => {
            const val = text.value.trim()
            if (/^#[0-9a-fA-F]{6}$/.test(val)) picker.value = val
          })
        }
      }
    </script>
    """
  end

  @impl true
  def handle_event("save_brand", %{"brand" => params}, socket) do
    # Note: logo is managed via the separate upload_logo / remove_logo events,
    # so it must NOT be part of brand_fields — otherwise saving would wipe it.
    brand_fields = [
      {"brand_name", params["name"]},
      {"brand_tagline", params["tagline"]},
      {"brand_description", params["description"]},
      {"brand_contact_email", params["contact_email"]},
      {"brand_contact_phone", params["contact_phone"]},
      {"handle_prefix", params["handle_prefix"]}
    ]

    # Prefer the text field value over the color picker (both send the same name;
    # if primary_color_text is present and non-empty, use it, else fall back to primary_color)
    color =
      case params["primary_color_text"] do
        v when is_binary(v) and byte_size(v) > 0 -> String.trim(v)
        _ -> params["primary_color"]
      end

    Enum.each(brand_fields, fn {key, val} ->
      Settings.put(key, (val && String.trim(val)) || "")
    end)

    if color && String.trim(color) != "" do
      Settings.put("brand_primary_color", String.trim(color))
    end

    brand = Settings.brand_settings()

    {:noreply,
     socket
     |> assign(:brand_form, to_form(brand_form_params(brand), as: :brand))
     |> put_flash(:info, "Brand settings saved.")}
  end

  # ── Logo upload / removal ───────────────────────────────────────────────────

  @impl true
  def handle_event("validate_logo", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("upload_logo", _params, socket) do
    bucket = Settings.storage_bucket()

    result =
      consume_uploaded_entries(socket, :logo, fn %{path: tmp_path}, entry ->
        ext = entry.client_name |> Path.extname() |> String.downcase()
        key = "brand/logo#{ext}"
        content = File.read!(tmp_path)

        case Uploader.upload(key, content, mime_type: entry.client_type) do
          {:ok, _} ->
            {:ok, Uploader.presign_url(bucket, key)}

          {:error, reason} ->
            require Logger
            Logger.error("Logo upload failed: #{inspect(reason)}")
            {:error, reason}
        end
      end)

    case result do
      [url | _] when is_binary(url) ->
        Settings.put("brand_logo_url", url)

        {:noreply,
         socket
         |> assign(:brand_logo_url, url)
         |> put_flash(:info, "Logo uploaded. It is now used as the site logo and favicon.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Logo upload failed. Please try again.")}
    end
  end

  @impl true
  def handle_event("remove_logo", _params, socket) do
    Settings.put("brand_logo_url", "")

    {:noreply,
     socket
     |> assign(:brand_logo_url, nil)
     |> put_flash(:info, "Logo removed. Falling back to the default kiroku.ico.")}
  end

  @impl true
  def handle_event("cancel_logo_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :logo, ref)}
  end

  @impl true
  def handle_event("save_embargo", %{"embargo" => params}, socket) do
    cron = params["cron_schedule"] || ""
    cron = String.trim(cron)

    if cron != "" do
      Settings.put("embargo_cron_schedule", cron)
    end

    embargo = Settings.embargo_settings()

    {:noreply,
     socket
     |> assign(:embargo_form, to_form(embargo_form_params(embargo), as: :embargo))
     |> put_flash(
       :info,
       "Embargo schedule saved. Restart the application for the new schedule to take effect."
     )}
  end

  @impl true
  def handle_event("run_embargo_lifter", _params, socket) do
    %{}
    |> Kiroku.Embargo.LifterWorker.new()
    |> Oban.insert()

    {:noreply,
     put_flash(
       socket,
       :info,
       "Embargo lifter job enqueued. Check the Oban dashboard for results."
     )}
  end

  @impl true
  def handle_event("storage_changed", %{"storage" => params}, socket) do
    adapter = if params["adapter"] == "s3", do: :s3, else: :local

    {:noreply,
     socket
     |> assign(:storage_adapter, adapter)
     |> assign(:storage_form, to_form(params, as: :storage))}
  end

  @impl true
  def handle_event("save_storage", %{"storage" => params}, socket) do
    fields = [
      {"storage_adapter", params["adapter"]},
      {"storage_bucket", params["bucket"]},
      {"storage_region", params["region"]},
      {"storage_endpoint", params["endpoint"]},
      {"storage_public_url", params["public_url"]},
      {"storage_access_key_id", params["access_key_id"]}
    ]

    # Only update secret_access_key if a non-empty value is provided
    secret_fields =
      case params["secret_access_key"] do
        "" -> []
        nil -> []
        val -> [{"storage_secret_access_key", val}]
      end

    Enum.each(fields ++ secret_fields, fn {key, val} ->
      if val && String.trim(val) != "" do
        Settings.put(key, String.trim(val))
      end
    end)

    # Persist adapter even if empty (to allow explicit :local)
    Settings.put("storage_adapter", params["adapter"] || "local")

    adapter = if params["adapter"] == "s3", do: :s3, else: :local

    {:noreply,
     socket
     |> assign(:storage_adapter, adapter)
     |> put_flash(:info, "Storage settings saved.")}
  end

  @impl true
  def handle_event("save_submission", %{"submission" => params}, socket) do
    allowed = params["allow_user_submit"] == "true"
    reg = params["allow_registration"] == "true"

    Settings.put("allow_user_submit", if(allowed, do: "true", else: "false"))
    Settings.put("allow_registration", if(reg, do: "true", else: "false"))

    messages =
      []
      |> Kernel.++(
        if reg, do: ["Self-registration enabled."], else: ["Self-registration disabled."]
      )
      |> Kernel.++(
        if allowed, do: ["User submissions enabled."], else: ["User submissions disabled."]
      )

    {:noreply,
     socket
     |> assign(:allow_submit, allowed)
     |> assign(:allow_registration, reg)
     |> put_flash(:info, Enum.join(messages, " "))}
  end

  @impl true
  def handle_event("save_file_locks", params, socket) do
    locked = params["locked"] || []
    descriptions = if is_list(locked), do: locked, else: [locked]
    mode = if params["mode"] == "closed", do: :closed, else: :internal

    Settings.put_locked_bitstream_descriptions(descriptions)
    Settings.put_file_lock_mode(mode)

    mode_label = if mode == :closed, do: "superadmin only", else: "internal + staff"

    {:noreply,
     socket
     |> assign(:locked_descriptions, descriptions)
     |> assign(:file_lock_mode, mode)
     |> put_flash(
       :info,
       "File access controls saved. #{length(descriptions)} file type(s) locked (#{mode_label})."
     )}
  end

  @impl true
  def handle_event("mailer_changed", %{"mailer" => params}, socket) do
    adapter = params["provider"] || "local"

    {:noreply,
     socket
     |> assign(:mailer_adapter, adapter)
     |> assign(:mailer_form, to_form(params, as: :mailer))}
  end

  @impl true
  def handle_event("save_mailer", %{"mailer" => params}, socket) do
    Settings.put("mailer_provider", params["provider"] || "local")
    put_if_present("mailer_from", params["from"])
    put_if_present("smtp_host", params["host"])
    put_if_present("smtp_port", params["port"])
    put_if_present("smtp_username", params["username"])

    case params["password"] do
      v when is_binary(v) and v != "" -> Settings.put("smtp_password", v)
      _ -> :ignore
    end

    # Re-apply the mailer config so the new provider/credentials take effect.
    Kiroku.Mailer.ConfigWorker.refresh()

    mailer = Settings.mailer_settings()
    adapter = params["provider"] || "local"

    {:noreply,
     socket
     |> assign(:mailer_adapter, adapter)
     |> assign(:mailer_form, to_form(mailer_form_params(mailer), as: :mailer))
     |> put_flash(:info, "Mailer settings saved.")}
  end

  defp put_if_present(_key, val) when val in [nil, ""], do: :ignore
  defp put_if_present(key, val), do: Settings.put(key, String.trim(val))

  defp storage_form_params(settings) do
    %{
      "adapter" => to_string(settings.adapter),
      "bucket" => settings.bucket || "",
      "region" => settings.region || "",
      "endpoint" => settings.endpoint || "",
      "public_url" => settings.public_url || "",
      "access_key_id" => settings.access_key_id || "",
      "secret_access_key" => ""
    }
  end

  defp brand_form_params(brand) do
    %{
      "name" => brand.name || "",
      "tagline" => brand.tagline || "",
      "description" => brand.description || "",
      "contact_email" => brand.contact_email || "",
      "contact_phone" => brand.contact_phone || "",
      "handle_prefix" => Settings.handle_prefix(),
      "primary_color" => brand.primary_color || "#7B4FA6"
    }
  end

  defp embargo_form_params(embargo) do
    %{
      "cron_schedule" => embargo.cron_schedule || ""
    }
  end

  defp mailer_form_params(mailer) do
    %{
      "provider" => mailer.provider || "local",
      "from" => mailer.from || "",
      "host" => mailer.host || "",
      "port" => to_string(mailer.port || ""),
      "username" => mailer.username || "",
      "password" => ""
    }
  end

  defp upload_error_to_string(:too_large), do: "File is too large (max 2 MB)"
  defp upload_error_to_string(:not_accepted), do: "File type not accepted"
  defp upload_error_to_string(:too_many_files), do: "Too many files"
  defp upload_error_to_string(err), do: "Upload error: #{inspect(err)}"
end
