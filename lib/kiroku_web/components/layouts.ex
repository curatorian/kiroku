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

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header style="background: var(--color-grimoire); border-bottom: 1px solid rgba(155,126,200,0.12);">
      <nav class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8 flex items-center justify-between h-16">
        <%!-- Wordmark --%>
        <a href={~p"/"} class="flex items-center gap-2 group">
          <span class="kiroku-kanji text-2xl leading-none">記</span>
          <span class="kiroku-wordmark text-xl leading-none">Kiroku</span>
        </a>

        <%!-- Main nav --%>
        <div
          class="hidden md:flex items-center gap-6 text-sm font-medium"
          style="color: var(--color-wisteria);"
        >
          <a href={~p"/communities"} class="hover:text-white transition-colors">Communities</a>
          <a href={~p"/search"} class="hover:text-white transition-colors flex items-center gap-1">
            <.icon name="hero-magnifying-glass" class="w-4 h-4" /> Search
          </a>
        </div>

        <%!-- Right side --%>
        <div class="flex items-center gap-3">
          <%= if @current_scope do %>
            <span class="text-sm" style="color: var(--color-dust);">{@current_scope.email}</span>
            <a
              href={~p"/my/items"}
              class="text-sm px-3 py-1.5 rounded-lg transition-colors"
              style="background: rgba(123,79,166,0.15); color: var(--color-lavender); border: 1px solid rgba(123,79,166,0.25);"
            >
              My Items
            </a>
            <.link
              href={~p"/users/log_out"}
              method="delete"
              class="text-sm px-3 py-1.5 rounded-lg transition-colors"
              style="color: var(--color-dust);"
            >
              Sign out
            </.link>
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

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
