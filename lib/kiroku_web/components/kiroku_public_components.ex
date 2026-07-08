defmodule KirokuWeb.KirokuPublicComponents do
  @moduledoc """
  UI components for the public-facing frontend.

  Includes item cards, community/collection cards, and the search bar.
  These are used in public controllers and LiveViews accessible without login.
  """
  use Phoenix.Component
  use Gettext, backend: KirokuWeb.Gettext

  import KirokuWeb.KirokuComponents
  import KirokuWeb.CoreComponents, only: [icon: 1]

  # ── Item Card ─────────────────────────────────────────────────────────────

  @doc """
  Renders a compact item card for search results and collection listings.

  Displays the item type badge, status badge, title, authors, and date.
  The entire card is a link to the item detail page.

  ## Examples

      <.item_card item={@item} />
      <.item_card item={@item} navigate={~p"/items/\#{@item.id}"} />
  """
  attr :item, :map, required: true
  attr :navigate, :string, default: nil

  def item_card(assigns) do
    ~H"""
    <.link
      navigate={@navigate || "/items/#{@item.handle}"}
      class="kiroku-card p-4 flex gap-4 items-start block transition-all duration-200"
      style="text-decoration: none;"
      onmouseover="this.style.borderColor='rgba(155,126,200,0.35)'; this.style.boxShadow='0 0 20px rgba(123,79,166,0.15)'"
      onmouseout="this.style.borderColor=''; this.style.boxShadow=''"
    >
      <div class="min-w-0 flex-1 space-y-2">
        <div class="flex items-center gap-2 flex-wrap">
          <.item_type_badge type={@item.item_type} />
          <.status_badge status={@item.status} />
          <%= if @item.publication_year do %>
            <span
              class="text-xs px-2 py-0.5 rounded-full"
              style="background: rgba(155,126,200,0.08); color: var(--color-wisteria);"
            >
              {@item.publication_year}
            </span>
          <% end %>
        </div>

        <p class="font-heading text-base leading-snug" style="color: var(--color-wisteria);">
          {@item.title}
        </p>

        <%!-- Abstract (truncated) --%>
        <%= if @item.abstract do %>
          <% abstract_text = @item.abstract

          truncated_abstract =
            if String.length(abstract_text) > 150 do
              String.slice(abstract_text, 0, 147) <> "..."
            else
              abstract_text
            end %>
          <p
            class="text-sm leading-relaxed line-clamp-2"
            style="color: var(--color-quill);"
          >
            {truncated_abstract}
          </p>
        <% end %>

        <%!-- Author information --%>
        <%= if @item.student_name do %>
          <div class="flex items-center gap-2">
            <div
              class="w-7 h-7 rounded-full flex items-center justify-center shrink-0 text-xs font-bold"
              style="background: rgba(123,79,166,0.2); color: var(--color-patchouli);"
            >
              {String.first(@item.student_name)}
            </div>
            <div class="flex-1 min-w-0">
              <p class="font-medium text-sm truncate" style="color: var(--color-wisteria);">
                {@item.student_name}
              </p>
              <%= if @item.student_id do %>
                <p class="font-mono text-xs truncate" style="color: var(--color-quill);">
                  NPM: {@item.student_id}
                </p>
              <% end %>
            </div>
          </div>
        <% end %>

        <%!-- Academic information --%>
        <div class="flex flex-wrap gap-2 text-xs" style="color: var(--color-quill);">
          <%= if @item.program_study do %>
            <span class="px-2 py-0.5 rounded" style="background: rgba(155,126,200,0.06);">
              {@item.program_study}
            </span>
          <% end %>
          <%= if @item.faculty do %>
            <span class="px-2 py-0.5 rounded" style="background: rgba(155,126,200,0.06);">
              {@item.faculty}
            </span>
          <% end %>
        </div>

        <%!-- Date information --%>
        <%= if not is_nil(@item.date_submitted) or not is_nil(@item.published_at) or not is_nil(@item.inserted_at) do %>
          <% display_date =
            cond do
              not is_nil(@item.date_submitted) -> @item.date_submitted
              not is_nil(@item.published_at) -> @item.published_at
              not is_nil(@item.inserted_at) -> @item.inserted_at
              true -> nil
            end

          date_label =
            cond do
              not is_nil(@item.date_submitted) -> "Submitted"
              not is_nil(@item.published_at) -> "Published"
              not is_nil(@item.inserted_at) -> "Created"
              true -> ""
            end %>
          <%= if display_date do %>
            <div class="flex items-center gap-1.5">
              <.icon
                name="hero-calendar"
                class="w-3.5 h-3.5 shrink-0"
                style="color: var(--color-dust);"
              />
              <span class="font-mono text-xs" style="color: var(--color-dust);">
                {date_label}: {Calendar.strftime(display_date, "%d %b %Y")}
              </span>
            </div>
          <% end %>
        <% end %>
      </div>
    </.link>
    """
  end

  # ── Community Card ────────────────────────────────────────────────────────

  @doc """
  Renders a community card for the public browse page.

  Displays the community's 記 kanji, name, handle, and short description.

  ## Examples

      <.community_card community={@community} />
      <.community_card community={@community} navigate={~p"/communities/\#{@community.handle}"} />
  """
  attr :community, :map, required: true
  attr :navigate, :string, default: nil

  def community_card(assigns) do
    ~H"""
    <.link
      navigate={@navigate || "/communities/#{@community.handle}"}
      class="kiroku-card-raised p-5 block transition-all duration-200"
      style="text-decoration: none;"
      onmouseover="this.style.borderColor='rgba(155,126,200,0.40)'"
      onmouseout="this.style.borderColor=''"
    >
      <div class="flex items-start gap-3">
        <span class="kiroku-kanji text-3xl shrink-0" style="opacity: 0.40;">記</span>
        <div class="min-w-0">
          <p class="font-heading text-base truncate" style="color: var(--color-lilac);">
            {@community.name}
          </p>
          <p class="kiroku-handle text-xs mt-0.5">{@community.handle}</p>
          <%= if @community.short_description do %>
            <p class="font-body text-xs mt-2 line-clamp-2" style="color: var(--color-quill);">
              {@community.short_description}
            </p>
          <% end %>
        </div>
      </div>
    </.link>
    """
  end

  # ── Collection Card ───────────────────────────────────────────────────────

  @doc """
  Renders a collection card for community detail and browse pages.

  ## Examples

      <.collection_card collection={@collection} />
      <.collection_card collection={@collection} navigate={~p"/collections/\#{@collection.handle}"} />
  """
  attr :collection, :map, required: true
  attr :navigate, :string, default: nil

  def collection_card(assigns) do
    ~H"""
    <.link
      navigate={@navigate || "/collections/#{@collection.handle}"}
      class="kiroku-card p-4 block transition-all duration-200"
      style="text-decoration: none;"
      onmouseover="this.style.borderColor='rgba(155,126,200,0.35)'"
      onmouseout="this.style.borderColor=''"
    >
      <p class="font-heading text-base" style="color: var(--color-lilac);">{@collection.name}</p>
      <p class="kiroku-handle text-xs mt-1">{@collection.handle}</p>
      <%= if @collection.description do %>
        <p class="font-body text-xs mt-2 line-clamp-2" style="color: var(--color-quill);">
          {@collection.description}
        </p>
      <% end %>
    </.link>
    """
  end

  # ── Search Bar ────────────────────────────────────────────────────────────

  @doc """
  Renders a search input form.

  Submits a GET request to `action` with the query as the `q` parameter.

  ## Examples

      <.search_bar />
      <.search_bar value={@query} placeholder="Search items…" />
      <.search_bar value={@query} action="/search" />
  """
  attr :value, :string, default: ""
  attr :action, :string, default: "/search"
  attr :placeholder, :string, default: "Search by title, author, keyword…"

  def search_bar(assigns) do
    ~H"""
    <form action={@action} method="get" class="flex gap-2">
      <input
        type="text"
        name="q"
        value={@value}
        placeholder={@placeholder}
        class="kiroku-search-input flex-1"
      />
      <button
        type="submit"
        class="px-5 py-2.5 rounded-lg font-ui font-semibold text-sm shrink-0 transition-colors duration-150"
        style="background: var(--color-patchouli); color: white;"
        onmouseover="this.style.background='var(--color-lavender)'"
        onmouseout="this.style.background='var(--color-patchouli)'"
      >
        <span class="hero-magnifying-glass w-4 h-4 inline-block align-middle"></span> Cari
      </button>
    </form>
    """
  end
end
