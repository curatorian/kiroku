defmodule KirokuWeb.SearchLive do
  use KirokuWeb, :live_view

  import KirokuWeb.KirokuPublicComponents
  import KirokuWeb.KirokuComponents

  alias Kiroku.Repository
  alias Kiroku.Access.Authorization
  alias Kiroku.Pagination

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Search — Kiroku")
     |> assign(:items, [])
     |> assign(:facets, empty_facets())
     |> assign(:pagination, Pagination.build(0, 1, 20))
     |> assign(:query, nil)
     |> assign(:filters, %{})}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    query = params["q"]

    filters = %{
      item_type: params["type"],
      faculty: params["faculty"],
      department: params["department"],
      year: params["year"] && parse_year(params["year"]),
      collection_id: params["collection_id"],
      author: params["author"],
      keyword: params["keyword"],
      page: parse_page(params["page"])
    }

    scope = Authorization.visibility_scope(socket.assigns[:current_user])
    search_active = query || Enum.any?(filters, fn {_k, v} -> v not in [nil, 1] end)

    # Always fetch facets (scoped to visibility) so the sidebar is populated
    # even before a search — users can browse by clicking facet values.
    facet_params = Map.merge(filters, %{term: query, scope: scope})
    facets = Repository.facets(facet_params)

    if search_active do
      {items, pagination} = Repository.search_items_pagination(facet_params)

      {:noreply,
       socket
       |> assign(:query, query)
       |> assign(:filters, filters)
       |> assign(:items, items)
       |> assign(:facets, facets)
       |> assign(:pagination, pagination)}
    else
      {:noreply,
       socket
       |> assign(:query, nil)
       |> assign(:filters, filters)
       |> assign(:items, [])
       |> assign(:facets, facets)
       |> assign(:pagination, Pagination.build(0, 1, 20))}
    end
  end

  @impl true
  def handle_event("search", params, socket) do
    query_params =
      params
      |> Enum.reject(fn {_k, v} -> v == "" end)
      |> Enum.into(%{})

    {:noreply, push_patch(socket, to: ~p"/search?#{query_params}")}
  end

  @impl true
  def handle_event("clear-filters", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/search")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_user}>
      <div class="space-y-6">
        <%!-- Page header --%>
        <div>
          <h1 class="font-heading text-3xl font-semibold" style="color: var(--color-lilac);">
            Search
          </h1>
          <p class="mt-1 text-sm" style="color: var(--color-quill);">
            Search across all published works in the repository.
          </p>
        </div>

        <%!-- Search form --%>
        <form id="search-form" phx-submit="search" class="space-y-3">
          <div class="flex gap-2">
            <input
              type="text"
              name="q"
              id="search-query"
              value={@query}
              placeholder="Search titles, abstracts, full-text, keywords…"
              class="kiroku-search-input flex-1"
              autocomplete="off"
            />
            <button
              type="submit"
              class="px-5 py-2 rounded-lg font-medium text-sm transition-colors"
              style="background: var(--color-patchouli); color: white;"
            >
              Search
            </button>
          </div>
        </form>

        <%!-- Results + facet sidebar --%>
        <div class="grid gap-6 lg:grid-cols-[260px_1fr]">
          <%!-- Facet sidebar --%>
          <aside class="space-y-5 lg:sticky lg:top-6 lg:self-start">
            <%= if has_active_filters?(@filters) do %>
              <button
                phx-click="clear-filters"
                class="text-xs font-medium uppercase tracking-wide hover:underline"
                style="color: var(--color-wisteria);"
              >
                Clear all filters
              </button>
            <% end %>

            <.facet_group
              label="Type"
              values={@facets.item_types}
              selected={@filters[:item_type]}
              param="type"
              display={&item_type_label/1}
              current_query={@query}
              current_filters={@filters}
            />

            <.facet_group
              label="Year"
              values={@facets.years}
              selected={@filters[:year] && to_string(@filters[:year])}
              param="year"
              current_query={@query}
              current_filters={@filters}
            />

            <.facet_group
              label="Faculty"
              values={@facets.faculties}
              selected={@filters[:faculty]}
              param="faculty"
              current_query={@query}
              current_filters={@filters}
            />

            <.facet_group
              label="Author"
              values={@facets.authors}
              selected={@filters[:author]}
              param="author"
              current_query={@query}
              current_filters={@filters}
            />

            <.facet_group
              label="Subject / Keyword"
              values={@facets.keywords}
              selected={@filters[:keyword]}
              param="keyword"
              current_query={@query}
              current_filters={@filters}
            />
          </aside>

          <%!-- Results --%>
          <div>
            <%= if @query do %>
              <p class="text-sm mb-4" style="color: var(--color-quill);">
                Showing results for <span style="color: var(--color-wisteria);">"{@query}"</span>
                — {@pagination.total_count} result(s)
              </p>
            <% end %>

            <%= if @items == [] do %>
              <div class="kiroku-card p-12 text-center">
                <span class="kiroku-kanji text-5xl opacity-30">記</span>
                <p class="mt-4" style="color: var(--color-quill);">
                  {if @query,
                    do: "No results found. Try different keywords.",
                    else: "Search above, or browse using the filters on the left."}
                </p>
              </div>
            <% else %>
              <div class="space-y-3">
                <%= for item <- @items do %>
                  <.item_card item={item} />
                <% end %>
              </div>

              <.pagination
                pagination={@pagination}
                path="/search"
                params={build_search_params(@query, @filters)}
              />
            <% end %>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # ── Facet component ────────────────────────────────────────────────────────

  attr :label, :string, required: true
  attr :values, :list, required: true
  attr :selected, :any, default: nil
  attr :param, :string, required: true
  attr :display, :any, default: nil
  attr :current_query, :string, default: nil
  attr :current_filters, :map, default: %{}

  def facet_group(assigns) do
    ~H"""
    <%= if @values != [] do %>
      <div class="space-y-2">
        <h3
          class="text-xs font-semibold uppercase tracking-widest"
          style="color: var(--color-quill);"
        >
          {@label}
        </h3>
        <ul class="space-y-0.5">
          <%= for entry <- @values do %>
            <li>
              <%!-- Build a link that toggles this facet value on/off. Clicking
                   an already-selected value clears it. --%>
              <.link
                patch={facet_toggle_path(@param, entry.value, @current_query, @current_filters)}
                class={[
                  "flex items-center justify-between text-sm rounded-md px-2 py-1 transition-colors",
                  facet_is_selected?(@selected, entry.value) &&
                    "font-medium",
                  facet_is_selected?(@selected, entry.value) &&
                    "bg-[color-mix(in_srgb,var(--color-patchouli)_18%,transparent)]"
                ]}
                style={
                  if facet_is_selected?(@selected, entry.value),
                    do:
                      "color: var(--color-wisteria); border-left: 2px solid var(--color-patchouli);",
                    else: "color: var(--color-lilac);"
                }
              >
                <span class="truncate">
                  {if @display, do: @display.(entry.value), else: entry.value}
                </span>
                <span
                  class="text-xs ml-2 tabular-nums shrink-0"
                  style="color: var(--color-quill);"
                >
                  {entry.count}
                </span>
              </.link>
            </li>
          <% end %>
        </ul>
      </div>
    <% end %>
    """
  end

  defp facet_is_selected?(selected, value) do
    selected != nil && to_string(selected) == to_string(value)
  end

  # Toggles a facet value. If the value is already the selected one, removes
  # it; otherwise replaces it. Other filters + the query term are preserved.
  #
  # URL param names differ from internal filter keys for one facet:
  #   URL `type`  ↔  filter `item_type`
  # so we translate via `param_to_filter_key/1`.
  defp facet_toggle_path(param, value, query, filters) do
    filter_key = param_to_filter_key(param)
    current_value = Map.get(filters, filter_key)

    new_filters =
      if current_value != nil && to_string(current_value) == to_string(value) do
        Map.delete(filters, filter_key)
      else
        Map.put(filters, filter_key, value)
      end

    params = build_search_params(query, new_filters)
    ~p"/search?#{params}"
  end

  defp param_to_filter_key("type"), do: :item_type
  defp param_to_filter_key(other), do: String.to_existing_atom(other)

  defp has_active_filters?(filters) do
    filters
    |> Map.delete(:page)
    |> Enum.any?(fn {_k, v} -> v not in [nil, ""] end)
  end

  defp empty_facets do
    %{item_types: [], years: [], faculties: [], authors: [], keywords: []}
  end

  # Translates internal item_type atoms to user-facing labels for the facet
  # sidebar. Mirrors the option list in the previous single-select UI.
  defp item_type_label(value) when is_atom(value), do: item_type_label(Atom.to_string(value))

  defp item_type_label("skripsi"), do: "Skripsi"
  defp item_type_label("tesis"), do: "Tesis"
  defp item_type_label("disertasi"), do: "Disertasi"
  defp item_type_label("tugas_akhir"), do: "Tugas Akhir"
  defp item_type_label("memorandum_hukum"), do: "Memorandum Hukum"
  defp item_type_label("studi_kasus"), do: "Studi Kasus"
  defp item_type_label("laporan_proyek"), do: "Laporan Proyek"
  defp item_type_label("karya_kreatif"), do: "Karya Kreatif"
  defp item_type_label("karya_teknologi"), do: "Karya Teknologi"
  defp item_type_label("jurnal_nasional"), do: "Jurnal Nasional"
  defp item_type_label("jurnal_internasional"), do: "Jurnal Internasional"
  defp item_type_label("prosiding"), do: "Prosiding"
  defp item_type_label("capstone"), do: "Capstone"
  defp item_type_label(other), do: other

  defp parse_page(nil), do: 1

  defp parse_page(p) do
    case Integer.parse(p) do
      {n, ""} when n > 0 -> n
      _ -> 1
    end
  end

  defp parse_year(nil), do: nil

  defp parse_year(y) do
    case Integer.parse(y) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp build_search_params(query, filters) do
    %{}
    |> maybe_param("q", query)
    |> maybe_param("type", filters[:item_type])
    |> maybe_param("faculty", filters[:faculty])
    |> maybe_param("department", filters[:department])
    |> maybe_param("year", filters[:year])
    |> maybe_param("collection_id", filters[:collection_id])
    |> maybe_param("author", filters[:author])
    |> maybe_param("keyword", filters[:keyword])
  end

  defp maybe_param(params, _key, nil), do: params
  defp maybe_param(params, _key, ""), do: params
  defp maybe_param(params, key, value), do: Map.put(params, key, value)
end
