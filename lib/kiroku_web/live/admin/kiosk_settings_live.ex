defmodule KirokuWeb.Admin.KioskSettingsLive do
  use KirokuWeb, :live_view

  alias Kiroku.Kiosk

  @impl true
  def mount(_params, _session, socket) do
    if superadmin?(socket) do
      socket =
        socket
        |> assign(:page_title, "Kiosk Settings")
        |> assign_form(form_values())

      {:ok, socket}
    else
      {:ok,
       socket
       |> put_flash(:error, "You do not have access to this page.")
       |> redirect(to: ~p"/admin")}
    end
  end

  @impl true
  def handle_event("save", %{"kiosk" => params}, socket) do
    Kiosk.put_announcement(blank_to_nil(params["announcement"]))
    Kiosk.put_contact(blank_to_nil(params["contact"]))
    Kiosk.put_maintenance(params["maintenance_enabled"] == "true", params["maintenance_message"])

    policies = %{
      "allow_save" => params["allow_save"] == "true",
      "allow_print" => params["allow_print"] == "true",
      "allow_copy" => params["allow_copy"] == "true",
      "watermark" => params["watermark"] == "true",
      "idle_seconds" => to_int(params["idle_seconds"], 600),
      "reader_idle_seconds" => to_int(params["reader_idle_seconds"], 900),
      "page_size_default" => to_int(params["page_size_default"], 20)
    }

    Kiosk.put_policies(policies)

    {:noreply,
     socket
     |> assign_form(form_values())
     |> put_flash(:info, "Kiosk settings saved.")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_user} page_title="Kiosk Settings">
      <div class="max-w-3xl space-y-6">
        <div class="kiroku-card p-6">
          <div class="flex items-center gap-2 mb-4">
            <.icon
              name="hero-device-phone-mobile"
              class="w-5 h-5"
              style="color: var(--color-patchouli);"
            />
            <h2 class="font-heading text-lg font-semibold" style="color: var(--color-lilac);">
              Kiosk fleet status &amp; client policies
            </h2>
          </div>
          <p class="text-sm mb-6" style="color: var(--color-dust);">
            These values are served from <code>GET /api/v1/kiosks/status</code>
            to every kiosk.
            Device tokens must be approved here before they read as <em>active</em>
            (otherwise <em>needs_reverify</em>). Deleting a device token in API Tokens reads as <em>revoked</em>.
          </p>

          <.form for={@form} id="kiosk-settings-form" phx-submit="save">
            <div class="space-y-4">
              <.input
                field={@form[:maintenance_enabled]}
                type="select"
                label="Maintenance state"
                options={[{"false", "Normal operation"}, {"true", "Maintenance mode"}]}
              />
              <.input field={@form[:maintenance_message]} type="text" label="Maintenance message" />
              <.input field={@form[:announcement]} type="text" label="Announcement" />
              <.input field={@form[:contact]} type="text" label="Contact" />

              <fieldset class="space-y-3 pt-2">
                <legend class="text-sm font-medium" style="color: var(--color-lilac);">
                  Policies
                </legend>
                <.input
                  field={@form[:allow_save]}
                  type="select"
                  label="Allow save"
                  options={[{"true", "Yes"}, {"false", "No"}]}
                />
                <.input
                  field={@form[:allow_print]}
                  type="select"
                  label="Allow print"
                  options={[{"true", "Yes"}, {"false", "No"}]}
                />
                <.input
                  field={@form[:allow_copy]}
                  type="select"
                  label="Allow copy"
                  options={[{"true", "Yes"}, {"false", "No"}]}
                />
                <.input
                  field={@form[:watermark]}
                  type="select"
                  label="Watermark"
                  options={[{"true", "Yes"}, {"false", "No"}]}
                />
                <.input field={@form[:idle_seconds]} type="number" label="Idle seconds" />
                <.input field={@form[:reader_idle_seconds]} type="number" label="Reader idle seconds" />
                <.input field={@form[:page_size_default]} type="number" label="Page size default" />
              </fieldset>

              <button
                type="submit"
                class="px-4 py-2 rounded-lg font-medium text-sm transition-all hover:brightness-110 active:scale-95"
                style="background: var(--color-patchouli); color: white;"
              >
                Save kiosk settings
              </button>
            </div>
          </.form>
        </div>
      </div>
    </Layouts.admin>
    """
  end

  defp assign_form(socket, values) do
    assign(socket, form: to_form(values, as: :kiosk))
  end

  # Flat scalar values for the form; booleans rendered as select options.
  defp form_values do
    maintenance = Kiosk.maintenance()
    %{announcement: announcement, contact: contact} = Kiosk.client_config()
    policies = Kiosk.policies()

    %{
      "maintenance_enabled" => to_string(!!maintenance["enabled"]),
      "maintenance_message" => maintenance["message"] || "",
      "announcement" => announcement || "",
      "contact" => contact || "",
      "allow_save" => to_string(policies["allow_save"]),
      "allow_print" => to_string(policies["allow_print"]),
      "allow_copy" => to_string(policies["allow_copy"]),
      "watermark" => to_string(policies["watermark"]),
      "idle_seconds" => to_string(policies["idle_seconds"]),
      "reader_idle_seconds" => to_string(policies["reader_idle_seconds"]),
      "page_size_default" => to_string(policies["page_size_default"])
    }
  end

  defp superadmin?(socket) do
    user = socket.assigns[:current_user]
    user && user.user_type == :superadmin
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(v), do: v

  defp to_int(nil, default), do: default

  defp to_int(v, default) do
    case Integer.parse(String.trim(to_string(v))) do
      {n, ""} -> n
      _ -> default
    end
  end
end
