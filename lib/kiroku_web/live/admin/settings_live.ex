defmodule KirokuWeb.Admin.SettingsLive do
  use KirokuWeb, :live_view

  alias Kiroku.Settings

  @impl true
  def mount(_params, _session, socket) do
    storage = Settings.storage_settings()
    brand = Settings.brand_settings()

    embargo = Settings.embargo_settings()
    mailer = Settings.mailer_settings()
    allow_submit = Settings.allow_user_submit?()

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
                  (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION, S3_BUCKET, S3_ENDPOINT, S3_PUBLIC_URL).
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
                  placeholder="ap-southeast-1 (or $AWS_REGION)"
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
                  placeholder="(leave blank to use $AWS_ACCESS_KEY_ID)"
                />

                <.input
                  field={@storage_form[:secret_access_key]}
                  type="password"
                  label="Secret Access Key"
                  placeholder="(leave blank to use $AWS_SECRET_ACCESS_KEY)"
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
              field={@brand_form[:logo_url]}
              type="text"
              label="Logo URL"
              placeholder="https://… (leave blank to use the text wordmark)"
            />

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
              User Submissions
            </h2>
            <p class="text-xs mt-1" style="color: var(--color-quill);">
              Control whether regular users can submit new items. Staff (admins) can always create items.
            </p>
          </div>

          <.form for={nil} id="submission-form" phx-submit="save_submission" class="space-y-4">
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
    brand_fields = [
      {"brand_name", params["name"]},
      {"brand_tagline", params["tagline"]},
      {"brand_description", params["description"]},
      {"brand_contact_email", params["contact_email"]},
      {"brand_contact_phone", params["contact_phone"]},
      {"brand_logo_url", params["logo_url"]}
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
    Settings.put("allow_user_submit", if(allowed, do: "true", else: "false"))

    {:noreply,
     socket
     |> assign(:allow_submit, allowed)
     |> put_flash(
       :info,
       if(allowed,
         do: "User submissions enabled.",
         else: "User submissions disabled."
       )
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
      "logo_url" => brand.logo_url || "",
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
end
