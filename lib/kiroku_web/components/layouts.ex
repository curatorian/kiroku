defmodule KirokuWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use KirokuWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :current_path, :string, default: "/", doc: "current URL path for locale switcher links"

  slot :inner_block, required: true

  def app(assigns) do
    assigns =
      assigns
      |> assign_new(:locale, fn ->
        Gettext.get_locale(KirokuWeb.Gettext) || "id"
      end)
      |> assign(:brand, Kiroku.Settings.brand_settings())

    ~H"""
    <header style="background: var(--color-grimoire); border-bottom: 1px solid rgba(155,126,200,0.12);">
      <nav class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8 flex items-center justify-between h-16">
        <%!-- Wordmark --%>
        <a href={~p"/"} class="flex items-center gap-2 group">
          <%= if @brand.logo_url do %>
            <img src={@brand.logo_url} alt={@brand.name} class="h-8 w-auto object-contain" />
          <% else %>
            <span class="kiroku-kanji text-2xl leading-none">記</span>
            <span class="kiroku-wordmark text-xl leading-none">{@brand.name}</span>
          <% end %>
        </a>

        <%!-- Main nav --%>
        <div
          class="hidden md:flex items-center gap-6 text-sm font-medium"
          style="color: var(--color-wisteria);"
        >
          <a
            :for={item <- nav_items()}
            href={item.href}
            class="hover:text-patchouli transition-colors flex items-center gap-1"
          >
            <.icon :if={item.icon} name={item.icon} class="w-4 h-4" />
            {item.label}
          </a>
        </div>

        <%!-- Right side --%>
        <div class="flex items-center gap-2">
          <.theme_toggle />
          <.locale_switcher current_locale={@locale} current_path={@current_path} />
          <%= if @current_scope do %>
            <.user_menu current_scope={@current_scope} />
          <% else %>
            <a
              href={~p"/users/log_in"}
              class="text-sm px-3 py-1.5 rounded-lg transition-colors"
              style="color: var(--color-lavender);"
            >
              Sign in
            </a>
            <a
              href={~p"/users/register"}
              class="text-sm px-4 py-1.5 rounded-lg font-medium transition-colors"
              style="background: var(--color-patchouli); color: white;"
            >
              Register
            </a>
          <% end %>
        </div>
      </nav>
      <%!-- Ribbon tricolor line --%>
      <div class="kiroku-ribbon"></div>
    </header>

    <main class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8 py-8">
      {render_slot(@inner_block)}
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Renders the admin shell layout: a fixed sidebar with navigation and a
  scrollable main content area. Use this for all `/admin/*` LiveViews.

  ## Examples

      <Layouts.admin flash={@flash} current_scope={@current_user} page_title="Dashboard">
        <h1>Content</h1>
      </Layouts.admin>

  """
  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil
  attr :page_title, :string, default: "Admin"
  slot :inner_block, required: true

  def admin(assigns) do
    assigns = assign_new(assigns, :brand, fn -> Kiroku.Settings.brand_settings() end)

    ~H"""
    <div class="admin-shell">
      <%!-- Sidebar --%>
      <aside class="admin-sidebar">
        <%!-- Wordmark --%>
        <div class="admin-sidebar-header">
          <a href={~p"/"} class="flex items-center gap-2 group">
            <%= if @brand.logo_url do %>
              <img src={@brand.logo_url} alt={@brand.name} class="h-6 w-auto object-contain" />
            <% else %>
              <span class="kiroku-kanji text-xl leading-none">記</span>
              <span class="kiroku-wordmark text-base leading-none">{@brand.name}</span>
            <% end %>
          </a>
          <span
            class="ml-auto text-xs px-1.5 py-0.5 rounded font-ui font-semibold tracking-wide"
            style="background: color-mix(in srgb, var(--color-patchouli) 25%, transparent); color: var(--color-wisteria); border: 1px solid color-mix(in srgb, var(--color-patchouli) 30%, transparent);"
          >
            Admin
          </span>
        </div>

        <%!-- Nav --%>
        <nav class="admin-sidebar-nav">
          <.admin_nav_item
            icon="hero-squares-2x2"
            label="Dashboard"
            href={~p"/admin"}
            current_path={@page_title}
            match="Dashboard"
          />
          <.admin_nav_item
            icon="hero-document-text"
            label="Items"
            href={~p"/admin/items"}
            current_path={@page_title}
            match="Items"
          />
          <%= if @current_scope && @current_scope.user_type == :superadmin do %>
            <.admin_nav_item
              icon="hero-building-library"
              label="Communities"
              href={~p"/admin/communities"}
              current_path={@page_title}
              match="Communities"
            />
          <% end %>
          <.admin_nav_item
            icon="hero-folder-open"
            label="Collections"
            href={~p"/admin/collections"}
            current_path={@page_title}
            match="Collections"
          />
          <.admin_nav_item
            icon="hero-users"
            label="Users"
            href={~p"/admin/users"}
            current_path={@page_title}
            match="Users"
          />
          <%= if @current_scope && @current_scope.user_type in [:admin, :superadmin] do %>
            <%= if Kiroku.Sync.enabled?() do %>
              <.admin_nav_item
                icon="hero-arrow-path"
                label="Sync"
                href={~p"/admin/sync"}
                current_path={@page_title}
                match="Sync"
              />
            <% end %>
            <.admin_nav_item
              icon="hero-archive-box-arrow-down"
              label="SAF Import/Export"
              href={~p"/admin/saf"}
              current_path={@page_title}
              match="SAF"
            />
          <% end %>
          <div class="admin-sidebar-divider" />
          <.admin_nav_item
            icon="hero-cog-6-tooth"
            label="Settings"
            href={~p"/admin/settings"}
            current_path={@page_title}
            match="Settings"
          />
        </nav>

        <%!-- Footer --%>
        <div class="admin-sidebar-footer">
          <%= if @current_scope do %>
            <div class="flex items-center gap-2 min-w-0">
              <div
                class="flex-shrink-0 w-7 h-7 rounded-full flex items-center justify-center text-xs font-bold"
                style="background: color-mix(in srgb, var(--color-patchouli) 30%, transparent); color: var(--color-lavender);"
              >
                {String.first(@current_scope.display_name || @current_scope.email)
                |> String.upcase()}
              </div>
              <span class="text-xs truncate" style="color: var(--color-dust);">
                {@current_scope.email}
              </span>
            </div>
            <.link
              href={~p"/users/log_out"}
              method="delete"
              class="flex-shrink-0 p-1.5 rounded-lg transition-colors hover:bg-base-300"
              title="Sign out"
            >
              <.icon name="hero-arrow-right-on-rectangle" class="size-4 opacity-60" />
            </.link>
          <% end %>
        </div>
      </aside>

      <%!-- Main content --%>
      <div class="admin-main">
        <%!-- Top bar --%>
        <header class="admin-topbar">
          <h1 class="font-heading text-xl" style="color: var(--color-lilac);">{@page_title}</h1>
          <div class="flex items-center gap-3 ml-auto">
            <.theme_toggle />
            <.link
              href={~p"/"}
              class="flex items-center gap-1.5 text-xs px-3 py-1.5 rounded-lg transition-colors hover:bg-base-300"
              style="color: var(--color-dust);"
            >
              <.icon name="hero-arrow-top-right-on-square" class="size-3.5" /> View site
            </.link>
          </div>
        </header>

        <%!-- Page content --%>
        <main class="admin-content">
          {render_slot(@inner_block)}
        </main>
      </div>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Renders the first-run setup wizard shell: a centered layout with a brand
  wordmark, a step progress indicator, and flash messages.

  ## Examples

      <Layouts.setup flash={@flash} current_step={@step}>
        <h1>Content</h1>
      </Layouts.setup>
  """
  attr :flash, :map, required: true
  attr :current_step, :atom, default: :admin
  attr :brand, :map, default: %{}
  slot :inner_block, required: true

  def setup(assigns) do
    assigns =
      assigns
      |> assign_new(:brand, fn -> Kiroku.Settings.brand_settings() end)
      |> assign(:steps, setup_steps())

    ~H"""
    <div
      class="min-h-screen flex flex-col items-center justify-center px-4 py-10"
      style="background: var(--color-grimoire);"
    >
      <div class="w-full max-w-xl">
        <div class="flex items-center justify-center gap-2 mb-8">
          <%= if @brand[:logo_url] do %>
            <img src={@brand.logo_url} alt={@brand.name} class="h-8 w-auto object-contain" />
          <% else %>
            <span class="kiroku-kanji text-2xl leading-none">記</span>
            <span class="kiroku-wordmark text-xl leading-none">
              {@brand[:name] || "Kiroku"}
            </span>
          <% end %>
        </div>

        <.setup_progress steps={@steps} current={@current_step} />

        <div class="kiroku-card p-6 sm:p-8 mt-6">
          {render_slot(@inner_block)}
        </div>

        <p class="text-center text-xs mt-6" style="color: var(--color-dust);">
          Initial setup — required before the repository can be used.
        </p>
      </div>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  defp setup_steps do
    [
      %{key: :admin, label: "Admin"},
      %{key: :brand, label: "Brand"},
      %{key: :storage, label: "Storage"},
      %{key: :mailer, label: "Email"}
    ]
  end

  defp setup_progress(assigns) do
    ~H"""
    <div class="flex items-center justify-center gap-2">
      <%= for {step, index} <- Enum.with_index(@steps) do %>
        <% done? = step_index(@current, @steps) > index %>
        <% active? = @current == step.key %>
        <div class="flex items-center gap-2">
          <div
            class={[
              "flex items-center justify-center rounded-full text-xs font-semibold transition-all duration-200",
              "w-7 h-7",
              if(active?,
                do: "ring-2",
                else: if(done?, do: "", else: "")
              )
            ]}
            style={
              if active? do
                "background: var(--color-patchouli); color: white; --tw-ring-color: color-mix(in srgb, var(--color-patchouli) 40%, transparent);"
              else
                if done? do
                  "background: color-mix(in srgb, var(--color-patchouli) 30%, transparent); color: var(--color-lilac);"
                else
                  "background: rgba(155,126,200,0.08); color: var(--color-dust);"
                end
              end
            }
          >
            <%= if done? do %>
              <.icon name="hero-check" class="w-4 h-4" />
            <% else %>
              {index + 1}
            <% end %>
          </div>
          <span
            class="text-xs font-medium hidden sm:inline"
            style={if active?, do: "color: var(--color-lilac);", else: "color: var(--color-dust);"}
          >
            {step.label}
          </span>
          <%= if index < length(@steps) - 1 do %>
            <div class="w-6 h-px" style="background: rgba(155,126,200,0.2);"></div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  defp step_index(current, steps) do
    Enum.find_index(steps, fn s -> s.key == current end) || 0
  end

  # Nav items for the public top bar. Add, remove, or reorder entries here.
  # Set icon: nil for items without an icon.
  defp nav_items do
    [
      %{label: "Communities", href: ~p"/communities", icon: "hero-building-library"},
      %{label: "Search", href: ~p"/search", icon: "hero-magnifying-glass"}
    ]
  end

  # Private helper for the user avatar dropdown in the top nav
  defp user_menu(assigns) do
    ~H"""
    <div class="relative">
      <button
        phx-click={JS.toggle(to: "#user-menu-dropdown")}
        class="flex items-center justify-center size-8 rounded-full transition-all hover:ring-2 focus:outline-none focus:ring-2 cursor-pointer overflow-hidden"
        style="background: color-mix(in srgb, var(--color-patchouli) 30%, transparent); color: var(--color-lavender); --tw-ring-color: var(--color-lavender);"
        aria-haspopup="menu"
        aria-label="User menu"
      >
        <%= if @current_scope.avatar_url do %>
          <img src={@current_scope.avatar_url} alt="avatar" class="size-full object-cover" />
        <% else %>
          <span class="text-sm font-bold leading-none">
            {(@current_scope.display_name || @current_scope.email)
            |> String.first()
            |> String.upcase()}
          </span>
        <% end %>
      </button>

      <div
        id="user-menu-dropdown"
        phx-click-away={JS.hide(to: "#user-menu-dropdown")}
        class="hidden absolute right-0 mt-2 w-56 origin-top-right rounded-xl shadow-lg ring-1 z-50"
        style="background: var(--color-grimoire); border-color: color-mix(in srgb, var(--color-patchouli) 18%, transparent);"
        role="menu"
      >
        <%!-- User info header --%>
        <div
          class="px-4 py-3"
          style="border-bottom: 1px solid color-mix(in srgb, var(--color-patchouli) 12%, transparent);"
        >
          <p class="text-sm font-medium truncate" style="color: var(--color-lilac);">
            {@current_scope.display_name || @current_scope.email}
          </p>
          <%= if @current_scope.display_name do %>
            <p class="text-xs truncate mt-0.5" style="color: var(--color-dust);">
              {@current_scope.email}
            </p>
          <% end %>
        </div>

        <%!-- Menu items --%>
        <div class="py-1">
          <.link
            navigate={~p"/my/items"}
            class="flex items-center gap-2.5 px-4 py-2.5 text-sm transition-colors hover:bg-base-300"
            style="color: var(--color-wisteria);"
            role="menuitem"
          >
            <.icon name="hero-folder-open" class="size-4 flex-shrink-0" /> My Items
          </.link>
          <%= if @current_scope.user_type in [:admin, :superadmin] do %>
            <.link
              navigate={~p"/admin"}
              class="flex items-center gap-2.5 px-4 py-2.5 text-sm transition-colors hover:bg-base-300"
              style="color: var(--color-wisteria);"
              role="menuitem"
            >
              <.icon name="hero-squares-2x2" class="size-4 flex-shrink-0" /> Admin
            </.link>
          <% end %>
        </div>

        <%!-- Sign out --%>
        <div
          class="py-1"
          style="border-top: 1px solid color-mix(in srgb, var(--color-patchouli) 12%, transparent);"
        >
          <.link
            href={~p"/users/log_out"}
            method="delete"
            class="flex items-center gap-2.5 px-4 py-2.5 text-sm transition-colors hover:bg-base-300"
            style="color: var(--color-dust);"
            role="menuitem"
          >
            <.icon name="hero-arrow-right-on-rectangle" class="size-4 flex-shrink-0" /> Sign out
          </.link>
        </div>
      </div>
    </div>
    """
  end

  # Private helper for sidebar nav items
  defp admin_nav_item(assigns) do
    ~H"""
    <.link
      navigate={@href}
      class={[
        "admin-nav-item",
        String.contains?(@current_path, @match) && "admin-nav-item-active"
      ]}
    >
      <.icon name={@icon} class="size-4 flex-shrink-0" />
      {@label}
    </.link>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
