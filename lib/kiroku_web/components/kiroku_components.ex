defmodule KirokuWeb.KirokuComponents do
  @moduledoc """
  Common UI components shared across LiveViews and controllers.

  Includes status badges, item type badges, handles, empty states,
  page headers, breadcrumb navigation, and pagination.
  """

  use Phoenix.Component
  use Gettext, backend: KirokuWeb.Gettext

  import KirokuWeb.CoreComponents, only: [icon: 1]

  alias Kiroku.Pagination

  # ── Status Badge ──────────────────────────────────────────────────────────

  @doc """
  Renders a status badge for an item (published, embargoed, draft, etc.).

  ## Examples

      <.status_badge status={@item.status} />
      <.status_badge status="under_review" />
  """
  attr :status, :any, required: true

  def status_badge(assigns) do
    assigns = assign(assigns, :label, status_label(assigns.status))
    assigns = assign(assigns, :css_class, status_css(assigns.status))

    ~H"""
    <span class={["status-badge", @css_class]}>
      {@label}
    </span>
    """
  end

  defp status_label(status) do
    case to_string(status) do
      "published" -> "Published"
      "embargoed" -> "Embargoed"
      "draft" -> "Draft"
      "submitted" -> "Submitted"
      "under_review" -> "Under Review"
      "withdrawn" -> "Withdrawn"
      other -> String.capitalize(other)
    end
  end

  defp status_css(status) do
    case to_string(status) do
      "published" -> "published"
      "embargoed" -> "embargoed"
      "draft" -> "draft"
      "submitted" -> "submitted"
      "under_review" -> "under-review"
      "withdrawn" -> "withdrawn"
      _ -> "draft"
    end
  end

  # ── Item Type Badge ────────────────────────────────────────────────────────

  @doc """
  Renders a themed badge for an item type.

  Colors and labels follow the Kiroku element map from the brand guidelines.

  ## Examples

      <.item_type_badge type={@item.item_type} />
      <.item_type_badge type=":skripsi" />
  """
  attr :type, :any, required: true

  def item_type_badge(assigns) do
    assigns = assign(assigns, :label, type_label(assigns.type))
    assigns = assign(assigns, :style, type_style(assigns.type))

    ~H"""
    <span class="badge-item-type" style={@style}>
      {@label}
    </span>
    """
  end

  defp type_label(type) do
    case to_string(type) do
      "skripsi" -> "Skripsi"
      "memorandum_hukum" -> "Memo Hukum"
      "studi_kasus" -> "Studi Kasus"
      "laporan_proyek" -> "Laporan Proyek"
      "karya_kreatif" -> "Karya Kreatif"
      "karya_teknologi" -> "Karya Teknologi"
      "jurnal_nasional" -> "Jurnal SINTA"
      "jurnal_internasional" -> "Scopus / WoS"
      "prosiding" -> "Prosiding"
      "capstone" -> "Capstone"
      other -> String.capitalize(other)
    end
  end

  defp type_style(type) do
    case to_string(type) do
      "skripsi" ->
        "color: var(--color-wisteria); background: rgba(45,27,105,0.60); border-color: rgba(155,126,200,0.30);"

      "memorandum_hukum" ->
        "color: var(--color-ribbon-gold); background: rgba(212,160,23,0.15); border-color: rgba(212,160,23,0.30);"

      "studi_kasus" ->
        "color: var(--color-ribbon-blue); background: rgba(74,123,196,0.15); border-color: rgba(74,123,196,0.30);"

      "laporan_proyek" ->
        "color: var(--color-wisteria); background: rgba(45,27,105,0.60); border-color: rgba(155,126,200,0.30);"

      "karya_kreatif" ->
        "color: var(--color-ribbon-red); background: rgba(196,65,90,0.15); border-color: rgba(196,65,90,0.30);"

      "karya_teknologi" ->
        "color: var(--color-ribbon-sky); background: rgba(74,123,196,0.15); border-color: rgba(74,123,196,0.30);"

      "jurnal_nasional" ->
        "color: var(--color-ribbon-gold); background: rgba(212,160,23,0.15); border-color: rgba(212,160,23,0.30);"

      "jurnal_internasional" ->
        "color: var(--color-ribbon-amber); background: rgba(212,160,23,0.20); border-color: rgba(232,197,71,0.30);"

      "prosiding" ->
        "color: var(--color-ribbon-sky); background: rgba(122,171,216,0.15); border-color: rgba(122,171,216,0.30);"

      "capstone" ->
        "color: var(--color-lavender); background: rgba(155,126,200,0.15); border-color: rgba(155,126,200,0.30);"

      _ ->
        ""
    end
  end

  # ── Kiroku Handle ─────────────────────────────────────────────────────────

  @doc """
  Renders a handle, DOI, or identifier in monospace pill style.

  ## Examples

      <.kiroku_handle handle={@item.handle} />
      <.kiroku_handle handle="10.xxxx/kiroku.2024.0001" />
  """
  attr :handle, :string, required: true

  def kiroku_handle(assigns) do
    ~H"""
    <span class="kiroku-handle">{@handle}</span>
    """
  end

  # ── Empty State ───────────────────────────────────────────────────────────

  @doc """
  Renders a centered empty state with the 記 kanji watermark.

  ## Examples

      <.empty_state message="No items found." />

      <.empty_state message="Rak buku sedang lengang.">
        <.link navigate={~p"/my/items/new"}>Submit the first work</.link>
      </.empty_state>
  """
  attr :message, :string, default: "Rak buku sedang lengang."
  slot :inner_block

  def empty_state(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center py-20 gap-4 text-center">
      <span
        class="kiroku-kanji select-none"
        style="font-size: 6rem; line-height: 1; opacity: 0.06;"
      >
        記
      </span>
      <p class="font-body text-sm" style="color: var(--color-quill);">{@message}</p>
      <%= if @inner_block != [] do %>
        <div class="mt-2">
          {render_slot(@inner_block)}
        </div>
      <% end %>
    </div>
    """
  end

  # ── Page Header ───────────────────────────────────────────────────────────

  @doc """
  Renders a page header with title, optional subtitle, and an actions slot.

  ## Examples

      <.page_header title="Communities" />

      <.page_header title="Items" subtitle="All submitted works">
        <:actions>
          <.link navigate={~p"/admin/items/new"}>New Item</.link>
        </:actions>
      </.page_header>
  """
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  slot :actions

  def page_header(assigns) do
    ~H"""
    <div class="flex items-start justify-between mb-8">
      <div>
        <h1 class="font-heading text-3xl" style="color: var(--color-lilac);">{@title}</h1>
        <%= if @subtitle do %>
          <p class="font-body text-sm mt-1" style="color: var(--color-quill);">{@subtitle}</p>
        <% end %>
      </div>
      <%= if @actions != [] do %>
        <div class="flex items-center gap-2">
          {render_slot(@actions)}
        </div>
      <% end %>
    </div>
    """
  end

  # ── Breadcrumb ────────────────────────────────────────────────────────────

  @doc """
  Renders a breadcrumb navigation trail.

  Each item is a map with `:label` (required) and `:href` (optional).
  The last item without `:href` is treated as the current page.

  ## Examples

      <.breadcrumb items={[
        %{label: "Home", href: ~p"/"},
        %{label: "Communities", href: ~p"/communities"},
        %{label: @community.name}
      ]} />
  """
  attr :items, :list, required: true

  def breadcrumb(assigns) do
    ~H"""
    <nav
      class="flex items-center gap-1.5 font-ui text-xs mb-6"
      aria-label="Breadcrumb"
      style="color: var(--color-quill);"
    >
      <%= for {item, index} <- Enum.with_index(@items) do %>
        <%= if index > 0 do %>
          <span style="color: var(--color-dust);">›</span>
        <% end %>
        <%= if item[:href] do %>
          <.link
            navigate={item.href}
            class="transition-colors duration-150 hover:text-white"
            style="color: var(--color-lavender);"
          >
            {item.label}
          </.link>
        <% else %>
          <span style="color: var(--color-wisteria);" aria-current="page">{item.label}</span>
        <% end %>
      <% end %>
    </nav>
    """
  end

  # ── Pagination ─────────────────────────────────────────────────────────────

  @doc """
  Renders a reusable pagination control.

  Uses `<.link patch={...}>` so page navigation is URL-bookmarkable and
  integrates with `handle_params` in LiveViews.

  ## Attributes

    * `:pagination` — a `Kiroku.Pagination` struct (required)
    * `:path` — base route path, e.g. `"/admin/items"` (required)
    * `:params` — current query params as a map, e.g. `%{"status" => "submitted"}`.
      Page number is injected automatically; existing filters are preserved.

  ## Example

      <.pagination
        pagination={@pagination}
        path="/admin/items"
        params={%{"status" => @status_filter, "search" => @search_query}}
      />
  """
  attr :pagination, :map, required: true
  attr :path, :string, required: true
  attr :params, :map, default: %{}

  def pagination(assigns) do
    ~H"""
    <div :if={@pagination.total_pages > 1} class="flex items-center justify-center gap-1.5 mt-6">
      <%!-- Previous page --%>
      <.page_link
        path={@path}
        params={@params}
        page={@pagination.page - 1}
        disabled={!Pagination.has_prev?(@pagination)}
        aria_label="Previous page"
      >
        <.icon name="hero-chevron-left" class="w-4 h-4" />
      </.page_link>

      <%!-- Page numbers --%>
      <% current_page = @pagination.page %>
      <%= for item <- Pagination.page_list(@pagination) do %>
        <%= cond do %>
          <% item == :ellipsis -> %>
            <span class="px-2 text-sm select-none" style="color: var(--color-quill);">…</span>
          <% item == current_page -> %>
            <span
              class="min-w-[2.25rem] w-4 h-9 flex items-center justify-center rounded-lg text-sm font-semibold transition-all"
              style="background: var(--color-patchouli); color: white; box-shadow: 0 2px 6px rgba(123,79,166,0.3);"
              aria-current="page"
            >
              {item}
            </span>
          <% true -> %>
            <.page_link path={@path} params={@params} page={item}>
              {item}
            </.page_link>
        <% end %>
      <% end %>

      <%!-- Next page --%>
      <.page_link
        path={@path}
        params={@params}
        page={@pagination.page + 1}
        disabled={!Pagination.has_next?(@pagination)}
        aria_label="Next page"
      >
        <.icon name="hero-chevron-right" class="w-4 h-4" />
      </.page_link>
    </div>
    """
  end

  # Internal: single page link button (or disabled placeholder)
  attr :path, :string, required: true
  attr :params, :map, default: %{}
  attr :page, :integer, required: true
  attr :disabled, :boolean, default: false
  attr :aria_label, :string, default: nil
  slot :inner_block

  defp page_link(%{disabled: true} = assigns) do
    ~H"""
    <span
      class="min-w-[2.25rem] h-9 flex items-center justify-center rounded-lg text-sm cursor-not-allowed"
      style="color: var(--color-quill); opacity: 0.35;"
      aria-label={@aria_label}
      aria-disabled="true"
    >
      {render_slot(@inner_block)}
    </span>
    """
  end

  defp page_link(assigns) do
    ~H"""
    <.link
      patch={build_page_url(@path, @params, @page)}
      class="min-w-[2.25rem] h-9 flex items-center justify-center px-2 rounded-lg text-sm font-medium transition-all duration-150 hover:scale-105 active:scale-95"
      style="background: rgba(155,126,200,0.1); color: var(--color-wisteria);"
      aria-label={@aria_label || "Page #{@page}"}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  defp build_page_url(path, params, page) do
    query =
      params
      |> Map.put("page", page)
      |> Enum.reject(fn
        {_, nil} -> true
        {_, ""} -> true
        {"page", 1} -> true
        _ -> false
      end)
      |> Enum.map(fn {k, v} -> "#{k}=#{URI.encode_www_form(to_string(v))}" end)
      |> Enum.join("&")

    if query == "", do: path, else: "#{path}?#{query}"
  end
end
