defmodule KirokuWeb.SetupLive do
  @moduledoc """
  First-run onboarding wizard. Shown only when no superadmin exists and the
  `setup_complete` setting is absent. Gated by `KirokuWeb.Plugs.SetupGuard`.

  Steps: admin → brand → storage → mailer → done.
  """

  use KirokuWeb, :live_view

  alias Kiroku.Accounts.User
  alias Kiroku.{Onboarding, Settings}
  import Ecto.Changeset

  @impl true
  def mount(_params, _session, socket) do
    if Onboarding.setup_complete?() do
      {:ok, push_navigate(socket, to: ~p"/")}
    else
      socket =
        socket
        |> assign(:page_title, "Setup — Kiroku")
        |> assign(:step, :admin)
        |> assign(:brand, Settings.brand_settings())
        |> assign(:admin_form, to_form(admin_changeset(%{}), as: :admin))
        |> assign(:brand_form, to_form(brand_form_params(), as: :brand))
        |> assign(:storage_adapter, :local)
        |> assign(:storage_form, to_form(storage_form_params(), as: :storage))
        |> assign(:mailer_form, to_form(mailer_form_params(), as: :mailer))

      {:ok, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.setup flash={@flash} current_step={@step} brand={@brand}>
      <%= cond do %>
        <% @step == :admin -> %>
          <.step_header
            title="Create your administrator"
            subtitle="This account has full control over the repository. Choose a strong password (12+ characters)."
          />
          <.form
            for={@admin_form}
            id="setup-admin-form"
            phx-submit="next_admin"
            phx-change="validate_admin"
            class="space-y-4"
          >
            <.input field={@admin_form[:display_name]} type="text" label="Full name" required />
            <.input
              field={@admin_form[:email]}
              type="email"
              label="Email address"
              placeholder="admin@university.ac.id"
              required
            />
            <.input
              field={@admin_form[:password]}
              type="password"
              label="Password"
              autocomplete="new-password"
              required
            />
            <.input
              field={@admin_form[:password_confirmation]}
              type="password"
              label="Confirm password"
              autocomplete="new-password"
              required
            />
            <.step_actions next_label="Continue →" />
          </.form>
        <% @step == :brand -> %>
          <.step_header
            title="Brand your repository"
            subtitle="How your institution appears across the site. You can change all of this later under Settings."
          />
          <.form
            for={@brand_form}
            id="setup-brand-form"
            phx-submit="next_brand"
            phx-change="validate_brand"
            class="space-y-4"
          >
            <.input
              field={@brand_form[:name]}
              type="text"
              label="Repository / institution name"
              required
            />
            <.input field={@brand_form[:tagline]} type="text" label="Tagline" />
            <.input
              field={@brand_form[:contact_email]}
              type="email"
              label="Contact email"
              placeholder="repository@university.ac.id"
            />
            <.input field={@brand_form[:contact_phone]} type="text" label="Contact phone" />
            <.input
              field={@brand_form[:handle_prefix]}
              type="text"
              label="Handle prefix"
              placeholder="kandaga"
            />
            <p class="text-xs" style="color: var(--color-quill);">
              Used for DSpace-style handles, e.g. <code>kandaga/12345</code>. Default: <code>kandaga</code>.
            </p>
            <.step_actions back_event="back_brand" next_label="Continue →" />
          </.form>
        <% @step == :storage -> %>
          <.step_header
            title="File storage"
            subtitle="Where uploaded files are kept. Local disk works out of the box; S3 for production."
          />
          <.form
            for={@storage_form}
            id="setup-storage-form"
            phx-submit="next_storage"
            phx-change="validate_storage"
            class="space-y-4"
          >
            <div>
              <label class="block text-sm font-medium mb-1.5" style="color: var(--color-wisteria);">
                Storage adapter
              </label>
              <select
                name="storage[adapter]"
                class="kiroku-search-input w-full"
              >
                <option value="local" selected={@storage_adapter == :local}>
                  Local Disk (priv/uploads/)
                </option>
                <option value="s3" selected={@storage_adapter == :s3}>
                  S3 / S3-Compatible (AWS, MinIO, Cloudflare R2, etc.)
                </option>
              </select>
            </div>

            <%= if @storage_adapter == :s3 do %>
              <.input
                field={@storage_form[:bucket]}
                type="text"
                label="Bucket name"
                placeholder="kiroku-uploads"
              />
              <.input
                field={@storage_form[:region]}
                type="text"
                label="Region"
                placeholder="ap-southeast-1"
              />
              <.input
                field={@storage_form[:endpoint]}
                type="text"
                label="Custom endpoint URL"
                placeholder="https://minio.domain.com (optional)"
              />
              <.input field={@storage_form[:access_key_id]} type="text" label="Access key ID" />
              <.input
                field={@storage_form[:secret_access_key]}
                type="password"
                label="Secret access key"
              />
              <p class="text-xs" style="color: var(--color-quill);">
                Fields left blank fall back to environment variables
                (<code>S3_ACCESS_KEY_ID</code>, <code>S3_BUCKET</code>, etc.).
              </p>
            <% end %>

            <.step_actions back_event="back_storage" next_label="Continue →" />
          </.form>
        <% @step == :mailer -> %>
          <.step_header
            title="Email notifications"
            subtitle="Used for review notifications and password resets. Pick “Local” to skip sending for now."
          />
          <.form
            for={@mailer_form}
            id="setup-mailer-form"
            phx-submit="finish"
            phx-change="validate_mailer"
            class="space-y-4"
          >
            <div>
              <label class="block text-sm font-medium mb-1.5" style="color: var(--color-wisteria);">
                Email provider
              </label>
              <select name="mailer[provider]" class="kiroku-search-input w-full">
                <option value="local" selected={@mailer_form[:provider].value == "local"}>
                  Local (no sending — dev / staging)
                </option>
                <option value="smtp" selected={@mailer_form[:provider].value == "smtp"}>
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

            <%= if @mailer_form[:provider].value == "smtp" do %>
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
              <.input field={@mailer_form[:username]} type="text" label="SMTP username" />
              <.input field={@mailer_form[:password]} type="password" label="SMTP password" />
            <% end %>

            <.step_actions
              back_event="back_mailer"
              next_label="Finish setup ✓"
              submit_style="primary"
            />
          </.form>
        <% true -> %>
      <% end %>
    </Layouts.setup>
    """
  end

  # ── Step components ──────────────────────────────────────────────────────────

  attr :title, :string, required: true
  attr :subtitle, :string, default: nil

  defp step_header(assigns) do
    ~H"""
    <div class="mb-5">
      <h1 class="font-heading text-2xl" style="color: var(--color-lilac);">
        {@title}
      </h1>
      <%= if @subtitle do %>
        <p class="text-sm mt-1.5 leading-relaxed" style="color: var(--color-quill);">
          {@subtitle}
        </p>
      <% end %>
    </div>
    """
  end

  attr :back_event, :string, default: nil
  attr :next_label, :string, default: "Continue →"
  attr :submit_style, :string, default: "default"

  defp step_actions(assigns) do
    ~H"""
    <div class="flex items-center justify-between pt-3">
      <button
        :if={@back_event}
        type="button"
        phx-click={@back_event}
        class="px-4 py-2.5 rounded-lg font-medium text-sm transition-colors"
        style="background: rgba(155,126,200,0.1); color: var(--color-wisteria);"
      >
        ← Back
      </button>
      <span :if={is_nil(@back_event)}></span>
      <button
        type="submit"
        class="inline-flex items-center gap-2 px-5 py-2.5 rounded-lg font-semibold text-sm transition-all duration-150 hover:brightness-110 active:scale-95"
        style={
          if @submit_style == "primary",
            do:
              "background: var(--color-patchouli); color: white; box-shadow: 0 2px 8px rgba(123,79,166,0.35);",
            else: "background: color-mix(in srgb, var(--color-patchouli) 80%, black); color: white;"
        }
      >
        {@next_label}
      </button>
    </div>
    """
  end

  # ── Event handlers ───────────────────────────────────────────────────────────

  @impl true
  def handle_event("validate_admin", %{"admin" => params}, socket) do
    changeset = admin_changeset(params) |> Map.put(:action, :validate)
    {:noreply, assign(socket, :admin_form, to_form(changeset, as: :admin))}
  end

  def handle_event("next_admin", %{"admin" => params}, socket) do
    changeset = admin_changeset(params) |> Map.put(:action, :validate)

    if changeset.valid? do
      case Onboarding.create_first_superadmin(params) do
        {:ok, user} ->
          socket =
            socket
            |> assign(:step, :brand)
            |> assign(:created_admin_email, user.email)
            |> put_flash(:info, "Administrator account created.")

          {:noreply, socket}

        {:error, %Ecto.Changeset{} = cs} ->
          {:noreply, assign(socket, :admin_form, to_form(cs, as: :admin))}

        {:error, :superadmin_exists} ->
          {:noreply,
           socket
           |> put_flash(:error, "An admin already exists. Skipping account creation.")
           |> assign(:step, :brand)}
      end
    else
      {:noreply, assign(socket, :admin_form, to_form(changeset, as: :admin))}
    end
  end

  def handle_event("validate_brand", %{"brand" => params}, socket) do
    {:noreply, assign(socket, :brand_form, to_form(params, as: :brand))}
  end

  def handle_event("next_brand", %{"brand" => params}, socket) do
    save_brand_settings(params)
    socket = assign(socket, :brand, Settings.brand_settings())

    {:noreply, assign(socket, :step, :storage)}
  end

  def handle_event("back_brand", _params, socket) do
    {:noreply, assign(socket, :step, :admin)}
  end

  def handle_event("validate_storage", %{"storage" => params}, socket) do
    adapter = if params["adapter"] == "s3", do: :s3, else: :local

    {:noreply,
     socket
     |> assign(:storage_adapter, adapter)
     |> assign(:storage_form, to_form(params, as: :storage))}
  end

  def handle_event("next_storage", %{"storage" => params}, socket) do
    save_storage_settings(params)
    adapter = if params["adapter"] == "s3", do: :s3, else: :local

    {:noreply,
     socket
     |> assign(:storage_adapter, adapter)
     |> assign(:step, :mailer)}
  end

  def handle_event("back_storage", _params, socket) do
    {:noreply, assign(socket, :step, :brand)}
  end

  def handle_event("validate_mailer", %{"mailer" => params}, socket) do
    {:noreply, assign(socket, :mailer_form, to_form(params, as: :mailer))}
  end

  def handle_event("finish", %{"mailer" => params}, socket) do
    save_mailer_settings(params)
    Kiroku.Mailer.ConfigWorker.refresh()

    Onboarding.mark_setup_complete()

    {:noreply,
     socket
     |> put_flash(
       :info,
       "Setup complete! Sign in with your new administrator account to continue."
     )
     |> push_navigate(to: ~p"/users/log_in")}
  end

  def handle_event("back_mailer", _params, socket) do
    {:noreply, assign(socket, :step, :storage)}
  end

  # ── Settings persistence helpers ─────────────────────────────────────────────

  defp admin_changeset(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> validate_confirmation(:password, message: "does not match password")
  end

  defp save_brand_settings(params) do
    put_if_present("brand_name", params["name"])
    put_if_present("brand_tagline", params["tagline"])
    put_if_present("brand_description", params["description"])
    put_if_present("brand_contact_email", params["contact_email"])
    put_if_present("brand_contact_phone", params["contact_phone"])
    put_if_present("handle_prefix", params["handle_prefix"])
    put_if_present("brand_logo_url", params["logo_url"])
    put_if_present("brand_primary_color", params["primary_color"])
  end

  defp save_storage_settings(params) do
    Settings.put("storage_adapter", params["adapter"] || "local")
    put_if_present("storage_bucket", params["bucket"])
    put_if_present("storage_region", params["region"])
    put_if_present("storage_endpoint", params["endpoint"])
    put_if_present("storage_public_url", params["public_url"])
    put_if_present("storage_access_key_id", params["access_key_id"])

    case params["secret_access_key"] do
      v when is_binary(v) and v != "" -> Settings.put("storage_secret_access_key", v)
      _ -> :ignore
    end
  end

  defp save_mailer_settings(params) do
    Settings.put("mailer_provider", params["provider"] || "local")
    put_if_present("mailer_from", params["from"])
    put_if_present("smtp_host", params["host"])
    put_if_present("smtp_port", params["port"])
    put_if_present("smtp_username", params["username"])

    case params["password"] do
      v when is_binary(v) and v != "" -> Settings.put("smtp_password", v)
      _ -> :ignore
    end
  end

  defp put_if_present(_key, val) when val in [nil, ""], do: :ignore
  defp put_if_present(key, val), do: Settings.put(key, String.trim(val))

  # ── Form initialisation params ───────────────────────────────────────────────

  defp brand_form_params do
    brand = Settings.brand_settings()

    %{
      "name" => brand.name || "",
      "tagline" => brand.tagline || "",
      "description" => brand.description || "",
      "contact_email" => brand.contact_email || "",
      "contact_phone" => brand.contact_phone || "",
      "handle_prefix" => Settings.handle_prefix(),
      "logo_url" => brand.logo_url || "",
      "primary_color" => brand.primary_color || "#7B4FA6"
    }
  end

  defp storage_form_params do
    storage = Settings.storage_settings()

    %{
      "adapter" => to_string(storage.adapter),
      "bucket" => storage.bucket || "",
      "region" => storage.region || "",
      "endpoint" => storage.endpoint || "",
      "public_url" => storage.public_url || "",
      "access_key_id" => storage.access_key_id || "",
      "secret_access_key" => ""
    }
  end

  defp mailer_form_params do
    mailer = Settings.mailer_settings()

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
