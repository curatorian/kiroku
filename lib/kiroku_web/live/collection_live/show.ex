defmodule KirokuWeb.CollectionLive.Show do
  use KirokuWeb, :live_view

  import KirokuWeb.KirokuPublicComponents
  import KirokuWeb.KirokuComponents

  alias Kiroku.Repository
  alias Kiroku.Pagination

  @per_page 20

  @impl true
  def mount(%{"handle" => handle}, _session, socket) do
    collection = Repository.get_collection_by_handle!(handle)
    collection = Kiroku.Repo.preload(collection, :community)
    item_count = Repository.count_items_for_collection(collection.id)
    ancestor_chain = Repository.community_ancestor_chain(collection.community_id)

    # Distinct values used to populate the filter dropdowns
    filter_options = %{
      item_types: Repository.list_distinct_values_for_collection(collection.id, :item_type),
      years: Repository.list_distinct_values_for_collection(collection.id, :publication_year),
      faculties: Repository.list_distinct_values_for_collection(collection.id, :faculty),
      departments: Repository.list_distinct_values_for_collection(collection.id, :department),
      degree_levels: Repository.list_distinct_values_for_collection(collection.id, :degree_level)
    }

    {:ok,
     socket
     |> assign(:page_title, "#{collection.name} — Kiroku")
     |> assign(:collection, collection)
     |> assign(:item_count, item_count)
     |> assign(:ancestor_chain, ancestor_chain)
     |> assign(:filter_options, filter_options)
     |> assign(:items, [])
     |> assign(:filters, %{})
     |> assign(:pagination, Pagination.build(item_count, 1, @per_page))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    collection = socket.assigns.collection

    filters = %{
      term: params["q"],
      item_type: params["type"],
      year: params["year"] && parse_year(params["year"]),
      faculty: params["faculty"],
      department: params["department"],
      degree_level: params["degree"]
    }

    page = parse_page(params["page"])

    {items, pagination} =
      Repository.list_items_for_collection_pagination(
        collection.id,
        Keyword.put(filter_opts(filters), :page, page)
      )

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> assign(:items, items)
     |> assign(:pagination, pagination)}
  end

  @impl true
  def handle_event("filter", params, socket) do
    query_params =
      %{}
      |> maybe_param("q", params["q"])
      |> maybe_param("type", params["type"])
      |> maybe_param("year", params["year"])
      |> maybe_param("faculty", params["faculty"])
      |> maybe_param("department", params["department"])
      |> maybe_param("degree", params["degree"])

    {:noreply, push_patch(socket, to: collection_path(socket.assigns.collection, query_params))}
  end

  @impl true
  def handle_event("clear", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/collections/#{socket.assigns.collection.handle}")}
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

  defp filter_opts(filters) do
    # Enum values (item_type, degree_level) are passed as strings and rely on
    # Ecto.Enum casting inside the query, mirroring `search_live` — this avoids
    # `String.to_atom/1` on user-supplied URL params.
    [
      term: filters[:term],
      item_type: filters[:item_type],
      year: filters[:year],
      faculty: filters[:faculty],
      department: filters[:department],
      degree_level: filters[:degree_level],
      per_page: @per_page
    ]
  end

  defp collection_path(collection, query_params) do
    ~p"/collections/#{collection.handle}?#{query_params}"
  end

  defp maybe_param(params, _key, nil), do: params
  defp maybe_param(params, _key, ""), do: params
  defp maybe_param(params, key, value), do: Map.put(params, key, value)

  defp active_filter_count(filters) do
    filters
    |> Map.values()
    |> Enum.count(&(not is_nil(&1)))
  end

  defp type_label(type) do
    case to_string(type) do
      "skripsi" -> "Skripsi"
      "tesis" -> "Tesis"
      "disertasi" -> "Disertasi"
      "tugas_akhir" -> "Tugas Akhir"
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

  defp degree_label(degree) do
    case to_string(degree) do
      "d3" -> "D3 — Diploma"
      "d4" -> "D4 — Diploma"
      "s1" -> "S1 — Sarjana"
      "s1_terapan" -> "S1 Terapan"
      "s2" -> "S2 — Magister"
      "s3" -> "S3 — Doktoral"
      other -> String.upcase(other)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_user}>
      <div class="space-y-8">
        <%!-- Breadcrumb (full hierarchy via recursive CTE) --%>
        <nav class="flex items-center gap-1.5 text-xs flex-wrap" style="color: var(--color-quill);">
          <.link
            navigate={~p"/communities"}
            class="hover:text-[var(--color-patchouli)] transition-colors"
          >
            Communities
          </.link>
          <%= for ancestor <- @ancestor_chain do %>
            <.icon name="hero-chevron-right" class="w-3 h-3 shrink-0 opacity-50" />
            <.link
              navigate={~p"/communities/#{ancestor.handle}"}
              class="hover:text-[var(--color-patchouli)] transition-colors"
            >
              {ancestor.name}
            </.link>
          <% end %>
          <.icon name="hero-chevron-right" class="w-3 h-3 shrink-0 opacity-50" />
          <span style="color: var(--color-wisteria);">{@collection.name}</span>
        </nav>

        <%!-- Collection header --%>
        <div class="kiroku-card-raised p-8">
          <div class="flex items-start justify-between gap-4">
            <div>
              <h1 class="font-heading text-3xl font-semibold" style="color: var(--color-lilac);">
                {@collection.name}
              </h1>
              <p class="kiroku-handle mt-1">/{@collection.handle}</p>
              <%= if @collection.short_description do %>
                <p class="mt-3 leading-relaxed" style="color: var(--color-wisteria);">
                  {@collection.short_description}
                </p>
              <% end %>
            </div>
            <div class="text-right shrink-0">
              <p class="text-3xl font-bold" style="color: var(--color-patchouli);">
                {@item_count}
              </p>
              <p class="text-xs mt-0.5" style="color: var(--color-quill);">items</p>
            </div>
          </div>
        </div>

        <%!-- Filter & search panel --%>
        <form id="collection-filter-form" phx-change="filter" phx-submit="filter" class="space-y-3">
          <%!-- Search row --%>
          <div class="relative">
            <span
              class="absolute left-3 top-1/2 -translate-y-1/2 pointer-events-none"
              style="color: var(--color-quill);"
            >
              <.icon name="hero-magnifying-glass" class="w-4 h-4" />
            </span>
            <input
              type="text"
              name="q"
              id="collection-search"
              value={@filters[:term]}
              placeholder="Search titles & abstracts in this collection…"
              class="kiroku-search-input"
              style="padding-left: 2.5rem;"
              autocomplete="off"
              phx-debounce="400"
            />
          </div>

          <%!-- Filter dropdowns --%>
          <div class="flex flex-wrap gap-2.5">
            <.filter_select
              name="type"
              id="filter-type"
              label="All types"
              value={@filters[:item_type]}
              options={@filter_options[:item_types]}
              formatter={&type_label/1}
            />
            <.filter_select
              name="year"
              id="filter-year"
              label="All years"
              value={@filters[:year]}
              options={@filter_options[:years]}
            />
            <.filter_select
              name="degree"
              id="filter-degree"
              label="All levels"
              value={@filters[:degree_level]}
              options={@filter_options[:degree_levels]}
              formatter={&degree_label/1}
            />
            <.filter_select
              name="faculty"
              id="filter-faculty"
              label="All faculties"
              value={@filters[:faculty]}
              options={@filter_options[:faculties]}
            />
            <.filter_select
              name="department"
              id="filter-department"
              label="All departments"
              value={@filters[:department]}
              options={@filter_options[:departments]}
            />

            <%!-- Active filter count + clear --%>
            <%= if active_filter_count(@filters) > 0 do %>
              <button
                type="button"
                phx-click="clear"
                class="px-3 py-2 rounded-lg text-xs font-medium transition-colors flex items-center gap-1.5"
                style="background: rgba(196,65,90,0.10); color: var(--color-ribbon-red);"
              >
                <.icon name="hero-x-mark" class="w-3.5 h-3.5" />
                Clear ({active_filter_count(@filters)})
              </button>
            <% end %>
          </div>
        </form>

        <%!-- Results header --%>
        <div class="flex items-center justify-between">
          <h2 class="font-heading text-2xl" style="color: var(--color-lilac);">Items</h2>
          <span class="text-sm" style="color: var(--color-quill);">
            {@pagination.total_count}
            <%= if active_filter_count(@filters) > 0 do %>
              of {@item_count}
            <% end %>
            result(s)
          </span>
        </div>

        <%!-- Items list --%>
        <%= if @items == [] do %>
          <div class="kiroku-card p-8 text-center">
            <p style="color: var(--color-quill);">
              <%= if active_filter_count(@filters) > 0 do %>
                No items match your filters.
              <% else %>
                No published items in this collection yet.
              <% end %>
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
            path={"/collections/#{@collection.handle}"}
            params={build_filter_params(@filters)}
          />
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  # ── Filter select component ────────────────────────────────────────────────

  attr :name, :string, required: true
  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :value, :any, default: nil
  attr :options, :list, required: true
  attr :formatter, :any, default: nil

  defp filter_select(assigns) do
    ~H"""
    <select
      name={@name}
      id={@id}
      class="kiroku-search-input cursor-pointer"
      style="width: auto; padding: 0.5rem 2rem 0.5rem 0.75rem; font-size: 0.8125rem;"
    >
      <option value="">{@label}</option>
      <%= for opt <- @options do %>
        <% val = to_string(opt) %>
        <option value={val} selected={to_string(@value) == val}>
          {if @formatter, do: @formatter.(opt), else: opt}
        </option>
      <% end %>
    </select>
    """
  end

  defp build_filter_params(filters) do
    %{}
    |> maybe_param("q", filters[:term])
    |> maybe_param("type", filters[:item_type])
    |> maybe_param("year", filters[:year])
    |> maybe_param("faculty", filters[:faculty])
    |> maybe_param("department", filters[:department])
    |> maybe_param("degree", filters[:degree_level])
  end
end
