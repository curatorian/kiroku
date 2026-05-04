defmodule KirokuWeb.Admin.SettingsLive do
  use KirokuWeb, :live_view

  alias Kiroku.Settings

  @impl true
  def mount(_params, _session, socket) do
    settings = Settings.storage_settings()

    socket =
      socket
      |> assign(:page_title, "System Settings")
      |> assign(:storage_adapter, settings.adapter)
      |> assign(:storage_form, to_form(storage_form_params(settings), as: :storage))

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_user}>
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
                  (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION, S3_BUCKET, S3_ENDPOINT).
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
                  label="Custom Endpoint URL"
                  placeholder="https://… (optional — for MinIO, R2, etc.)"
                />

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
                class="px-5 py-2.5 rounded-lg font-semibold text-sm"
                style="background: var(--color-patchouli); color: white;"
              >
                Save Storage Settings
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
            </dl>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("storage_changed", %{"storage" => params}, socket) do
    adapter = if params["adapter"] == "s3", do: :s3, else: :local
    {:noreply, assign(socket, :storage_adapter, adapter)}
  end

  @impl true
  def handle_event("save_storage", %{"storage" => params}, socket) do
    fields = [
      {"storage_adapter", params["adapter"]},
      {"storage_bucket", params["bucket"]},
      {"storage_region", params["region"]},
      {"storage_endpoint", params["endpoint"]},
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

  defp storage_form_params(settings) do
    %{
      "adapter" => to_string(settings.adapter),
      "bucket" => settings.bucket || "",
      "region" => settings.region || "",
      "endpoint" => settings.endpoint || "",
      "access_key_id" => settings.access_key_id || "",
      "secret_access_key" => ""
    }
  end
end
