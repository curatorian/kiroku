defmodule KirokuWeb.BrowseLive do
  use KirokuWeb, :live_view

  import KirokuWeb.KirokuPublicComponents
  import KirokuWeb.KirokuComponents

  alias Kiroku.Repository
  alias Kiroku.Access.Authorization

  @moduledoc """
  Repository browse page.

  Supports four index modes via the `?by=` query param:
    * `structure` (default) — community → collection tree
    * `author`              — alphabetical author index with item counts
    * `date`                — year-by-year index with item counts
    * `title`               — alphabetical title index (paginated)

  Clicking an author/date/title links into /search with the matching filter
  so the existing search + facet infrastructure is reused for the result page.
  """

  @modes ~w(structure author date title)a

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Browse — Kiroku")
     |> assign(:mode, :structure)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    mode = parse_mode(params["by"])
    scope = Authorization.visibility_scope(socket.assigns[:current_user])

    socket =
      socket
      |> assign(:mode, mode)
      |> load_mode_data(mode, scope, params)

    {:noreply, socket}
  end

  defp load_mode_data(socket, :structure, scope, _params) do
    communities = Repository.list_communities_with_collections(scope: scope)
    assign(socket, communities: communities)
  end

  defp load_mode_data(socket, :author, scope, _params) do
    authors = Repository.browse_by_author(scope: scope, limit: 500)

    socket
    |> assign(authors: authors)
    |> assign(authors_by_letter: group_alphabetically(authors, & &1.value))
  end

  defp load_mode_data(socket, :date, scope, _params) do
    years = Repository.browse_by_date(scope: scope, limit: 100)
    assign(socket, years: years)
  end

  defp load_mode_data(socket, :title, scope, params) do
    page = parse_page(params["page"])
    {items, pagination} = Repository.browse_by_title(scope: scope, page: page, per_page: 20)

    socket
    |> assign(items: items)
    |> assign(pagination: pagination)
  end

  # ── Helpers ────────────────────────────────────────────────────────────────

  defp parse_mode(nil), do: :structure

  defp parse_mode(str) when is_binary(str) do
    atom = String.to_existing_atom(str)
    if atom in @modes, do: atom, else: :structure
  rescue
    ArgumentError -> :structure
  end

  defp parse_page(nil), do: 1

  defp parse_page(p) do
    case Integer.parse(p) do
      {n, ""} when n > 0 -> n
      _ -> 1
    end
  end

  # Groups entries by the first letter of `mapper.(entry)`. Non-Latin letters
  # are bucketed under the entry's first character (so "Å" gets its own group,
  # etc.). Returns `[{letter, [entries]}, ...]` sorted by letter.
  defp group_alphabetically(entries, mapper) do
    entries
    |> Enum.group_by(fn e ->
      e
      |> mapper.()
      |> to_string()
      |> String.first()
      |> case do
        nil -> "?"
        c -> String.upcase(c)
      end
    end)
    |> Enum.sort_by(fn {letter, _} -> letter end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_user}>
      <div class="space-y-8">
        <%!-- Page header --%>
        <div>
          <p
            class="text-sm font-medium uppercase tracking-widest mb-1"
            style="color: var(--color-patchouli);"
          >
            Browse
          </p>
          <h1 class="font-heading text-4xl font-semibold" style="color: var(--color-lilac);">
            Repository Index
          </h1>
          <p class="mt-2 text-sm" style="color: var(--color-quill);">
            Knowledge organized by faculty, author, date, or title.
          </p>
        </div>

        <%!-- Mode tabs --%>
        <.mode_tabs current={@mode} />

        <%!-- Mode content --%>
        <%= case @mode do %>
          <% :structure -> %>
            <.structure_mode communities={@communities} />
          <% :author -> %>
            <.author_mode authors_by_letter={@authors_by_letter} />
          <% :date -> %>
            <.date_mode years={@years} />
          <% :title -> %>
            <.title_mode items={@items} pagination={@pagination} />
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  # ── Mode tabs ──────────────────────────────────────────────────────────────

  attr :current, :atom, required: true

  defp mode_tabs(assigns) do
    ~H"""
    <div class="flex flex-wrap gap-2 border-b pb-3" style="border-color: rgba(155,126,200,0.12);">
      <.mode_tab id="structure" current={@current} label="By Structure" icon="hero-building-library" />
      <.mode_tab id="author" current={@current} label="By Author" icon="hero-users" />
      <.mode_tab id="date" current={@current} label="By Date" icon="hero-calendar" />
      <.mode_tab id="title" current={@current} label="By Title" icon="hero-list-bullet" />
    </div>
    """
  end

  attr :id, :string, required: true
  attr :current, :atom, required: true
  attr :label, :string, required: true
  attr :icon, :string, required: true

  defp mode_tab(assigns) do
    ~H"""
    <.link
      patch={~p"/browse?by=#{@id}"}
      class={[
        "flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-medium transition-all",
        @current == String.to_existing_atom(@id) &&
          "bg-[color-mix(in_srgb,var(--color-patchouli)_18%,transparent)]"
      ]}
      style={
        if @current == String.to_existing_atom(@id),
          do: "color: var(--color-wisteria); border-left: 2px solid var(--color-patchouli);",
          else: "color: var(--color-quill);"
      }
    >
      <.icon name={@icon} class="w-4 h-4" />
      {@label}
    </.link>
    """
  end

  # ── Structure mode (existing community/collection tree) ────────────────────

  attr :communities, :list, required: true

  defp structure_mode(assigns) do
    ~H"""
    <%= if @communities == [] do %>
      <div class="kiroku-card p-12 text-center">
        <span class="kiroku-kanji text-5xl opacity-30">記</span>
        <p class="mt-4" style="color: var(--color-quill);">
          No communities have been created yet.
        </p>
      </div>
    <% else %>
      <div class="space-y-8">
        <%= for community <- @communities do %>
          <div class="space-y-3">
            <div class="kiroku-card p-5">
              <div class="flex items-start gap-4">
                <div
                  class="w-12 h-12 rounded-xl flex items-center justify-center shrink-0"
                  style="background: rgba(123,79,166,0.2); color: var(--color-patchouli);"
                >
                  <.icon name="hero-academic-cap" class="w-6 h-6" />
                </div>
                <div class="flex-1 min-w-0">
                  <.link
                    navigate={~p"/communities/#{community.handle}"}
                    class="font-heading text-xl font-semibold hover:underline"
                    style="color: var(--color-lilac);"
                  >
                    {community.name}
                  </.link>
                  <p class="kiroku-handle mt-0.5">/{community.handle}</p>
                  <%= if community.short_description do %>
                    <p class="mt-1 text-sm" style="color: var(--color-quill);">
                      {community.short_description}
                    </p>
                  <% end %>
                </div>
              </div>
            </div>

            <%= if community.collections != [] do %>
              <div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-3 ml-4">
                <%= for collection <- community.collections do %>
                  <.link
                    navigate={~p"/collections/#{collection.handle}"}
                    class="kiroku-card p-4 flex items-center gap-3 hover:border-purple-500/40 transition-colors group"
                  >
                    <div
                      class="w-9 h-9 rounded-lg flex items-center justify-center shrink-0"
                      style="background: rgba(196,168,224,0.1); color: var(--color-wisteria);"
                    >
                      <.icon name="hero-folder-open" class="w-4 h-4" />
                    </div>
                    <div class="min-w-0">
                      <p
                        class="font-medium text-sm group-hover:text-white transition-colors"
                        style="color: var(--color-lilac);"
                      >
                        {collection.name}
                      </p>
                      <p class="kiroku-handle text-xs">{collection.handle}</p>
                    </div>
                  </.link>
                <% end %>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    <% end %>
    """
  end

  # ── Author mode ────────────────────────────────────────────────────────────

  attr :authors_by_letter, :list, required: true

  defp author_mode(assigns) do
    ~H"""
    <%= if @authors_by_letter == [] do %>
      <div class="kiroku-card p-12 text-center">
        <span class="kiroku-kanji text-5xl opacity-30">記</span>
        <p class="mt-4" style="color: var(--color-quill);">No authors indexed yet.</p>
      </div>
    <% else %>
      <div class="space-y-8">
        <%!-- Alphabet jump bar --%>
        <div class="flex flex-wrap gap-1 text-xs">
          <%= for {letter, _entries} <- @authors_by_letter do %>
            <a
              href={"#letter-#{letter}"}
              class="px-2 py-1 rounded font-mono hover:underline"
              style="color: var(--color-wisteria); background: rgba(155,126,200,0.08);"
            >
              {letter}
            </a>
          <% end %>
        </div>

        <%!-- Letter sections --%>
        <%= for {letter, entries} <- @authors_by_letter do %>
          <div id={"letter-#{letter}"} class="space-y-3">
            <h2
              class="font-heading text-2xl font-semibold sticky top-0 py-2"
              style="color: var(--color-patchouli); background: var(--color-void);"
            >
              {letter}
            </h2>
            <ul class="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
              <%= for entry <- entries do %>
                <li>
                  <.link
                    patch={~p"/search?author=#{entry.value}"}
                    class="kiroku-card p-3 flex items-center justify-between hover:border-purple-500/40 transition-colors group"
                  >
                    <span
                      class="text-sm truncate group-hover:text-white transition-colors"
                      style="color: var(--color-lilac);"
                    >
                      {entry.value}
                    </span>
                    <span
                      class="text-xs ml-2 tabular-nums shrink-0 px-2 py-0.5 rounded-full"
                      style="color: var(--color-quill); background: rgba(155,126,200,0.08);"
                    >
                      {entry.count}
                    </span>
                  </.link>
                </li>
              <% end %>
            </ul>
          </div>
        <% end %>
      </div>
    <% end %>
    """
  end

  # ── Date mode ──────────────────────────────────────────────────────────────

  attr :years, :list, required: true

  defp date_mode(assigns) do
    ~H"""
    <%= if @years == [] do %>
      <div class="kiroku-card p-12 text-center">
        <span class="kiroku-kanji text-5xl opacity-30">記</span>
        <p class="mt-4" style="color: var(--color-quill);">No dated items yet.</p>
      </div>
    <% else %>
      <ul class="space-y-2 max-w-md">
        <%= for entry <- @years do %>
          <li>
            <.link
              patch={~p"/search?year=#{entry.value}"}
              class="kiroku-card p-3 flex items-center justify-between hover:border-purple-500/40 transition-colors group"
            >
              <span
                class="font-heading text-lg font-medium group-hover:text-white transition-colors"
                style="color: var(--color-lilac);"
              >
                {entry.value}
              </span>
              <span
                class="text-sm tabular-nums px-3 py-1 rounded-full"
                style="color: var(--color-quill); background: rgba(155,126,200,0.08);"
              >
                {entry.count} {(entry.count == 1 && "item") || "items"}
              </span>
            </.link>
          </li>
        <% end %>
      </ul>
    <% end %>
    """
  end

  # ── Title mode ─────────────────────────────────────────────────────────────

  attr :items, :list, required: true
  attr :pagination, :map, required: true

  defp title_mode(assigns) do
    ~H"""
    <%= if @items == [] do %>
      <div class="kiroku-card p-12 text-center">
        <span class="kiroku-kanji text-5xl opacity-30">記</span>
        <p class="mt-4" style="color: var(--color-quill);">No published items yet.</p>
      </div>
    <% else %>
      <div class="space-y-3">
        <%= for item <- @items do %>
          <.item_card item={item} />
        <% end %>
      </div>

      <.pagination pagination={@pagination} path="/browse" params={%{"by" => "title"}} />
    <% end %>
    """
  end
end
