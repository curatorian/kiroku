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
      page: parse_page(params["page"])
    }

    scope = Authorization.visibility_scope(socket.assigns[:current_user])

    {items, pagination} =
      if query || Enum.any?(filters, fn {_k, v} -> v not in [nil, 1] end) do
        Repository.search_items_pagination(Map.merge(filters, %{term: query, scope: scope}))
      else
        {[], Pagination.build(0, 1, 20)}
      end

    {:noreply,
     socket
     |> assign(:query, query)
     |> assign(:filters, filters)
     |> assign(:items, items)
     |> assign(:pagination, pagination)}
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
        <form id="search-form" phx-submit="search" phx-change="search" class="space-y-3">
          <div class="flex gap-2">
            <input
              type="text"
              name="q"
              id="search-query"
              value={@query}
              placeholder="Search titles, abstracts, keywords…"
              class="kiroku-search-input flex-1"
              autocomplete="off"
              phx-debounce="400"
            />
            <button
              type="submit"
              class="px-5 py-2 rounded-lg font-medium text-sm transition-colors"
              style="background: var(--color-patchouli); color: white;"
            >
              Search
            </button>
          </div>
          <%!-- Filters row --%>
          <div class="flex flex-wrap gap-3">
            <select
              name="type"
              id="search-type"
              class="kiroku-search-input"
              style="width: auto; padding: 0.4rem 0.75rem;"
            >
              <option value="">All types</option>
              <option value="skripsi" selected={@filters[:item_type] == "skripsi"}>Skripsi</option>
              <option
                value="jurnal_nasional"
                selected={@filters[:item_type] == "jurnal_nasional"}
              >
                Jurnal Nasional
              </option>
              <option
                value="jurnal_internasional"
                selected={@filters[:item_type] == "jurnal_internasional"}
              >
                Jurnal Internasional
              </option>
              <option value="prosiding" selected={@filters[:item_type] == "prosiding"}>
                Prosiding
              </option>
              <option value="capstone" selected={@filters[:item_type] == "capstone"}>
                Capstone
              </option>
              <option value="karya_kreatif" selected={@filters[:item_type] == "karya_kreatif"}>
                Karya Kreatif
              </option>
              <option
                value="karya_teknologi"
                selected={@filters[:item_type] == "karya_teknologi"}
              >
                Karya Teknologi
              </option>
            </select>
            <input
              type="number"
              name="year"
              id="search-year"
              value={@filters[:year]}
              placeholder="Year"
              class="kiroku-search-input"
              style="width: 100px;"
              phx-debounce="600"
            />
            <input
              type="text"
              name="faculty"
              id="search-faculty"
              value={@filters[:faculty]}
              placeholder="Faculty"
              class="kiroku-search-input"
              style="width: auto;"
              phx-debounce="600"
            />
          </div>
        </form>

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
                  else: "Enter a search term to begin."}
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
    </Layouts.app>
    """
  end

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
  end

  defp maybe_param(params, _key, nil), do: params
  defp maybe_param(params, _key, ""), do: params
  defp maybe_param(params, key, value), do: Map.put(params, key, value)
end
