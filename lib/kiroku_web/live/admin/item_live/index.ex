defmodule KirokuWeb.Admin.ItemLive.Index do
  use KirokuWeb, :live_view

  import KirokuWeb.ItemForm
  import KirokuWeb.KirokuComponents

  alias Kiroku.Repository
  alias Kiroku.Repository.Item

  @statuses ~w(submitted published draft embargoed withdrawn)
  @item_types ~w(skripsi tesis disertasi tugas_akhir memorandum_hukum studi_kasus laporan_proyek karya_kreatif karya_teknologi jurnal_nasional jurnal_internasional prosiding capstone)

  # ── :index render ──────────────────────────────────────────────────────────

  def render(%{live_action: :index} = assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_user} page_title="Items">
      <div class="space-y-6">
        <div class="flex items-center justify-between">
          <h1 class="font-heading text-3xl" style="color: var(--color-lilac);">Items</h1>
          <.link
            patch={~p"/admin/items/new"}
            class="inline-flex items-center gap-2 px-4 py-2 rounded-lg font-medium text-sm transition-all hover:brightness-110"
            style="background: var(--color-patchouli); color: white;"
          >
            <.icon name="hero-plus" class="w-4 h-4" /> New Item
          </.link>
        </div>

        <%!-- Search and filters --%>
        <div class="kiroku-card p-4 space-y-4">
          <div class="flex flex-col sm:flex-row gap-3">
            <div class="flex-1">
              <.form for={@search_form} id="search-form" phx-change="search">
                <div class="relative">
                  <span class="absolute left-3 top-1/2 -translate-y-1/2">
                    <.icon
                      name="hero-magnifying-glass"
                      class="w-4 h-4"
                      style="color: var(--color-quill);"
                    />
                  </span>
                  <input
                    type="text"
                    name="search"
                    id="search-input"
                    value={@search_query}
                    placeholder="Search by title, handle, or student name..."
                    class="kiroku-search-input w-full"
                    style="padding-left: 2.5rem;"
                    autocomplete="off"
                  />
                  <button
                    :if={@search_query != ""}
                    type="button"
                    phx-click="clear_search"
                    class="absolute right-3 top-1/2 -translate-y-1/2 text-xs hover:text-white transition-colors"
                    style="color: var(--color-quill);"
                  >
                    Clear
                  </button>
                </div>
              </.form>
            </div>
            <div class="sm:w-48">
              <.form for={@filter_form} id="filter-form" phx-change="filter">
                <select
                  name="item_type"
                  id="item-type-select"
                  class="kiroku-search-input w-full"
                >
                  <option value="">All Types</option>
                  <%= for type <- @item_types do %>
                    <option value={type} selected={@item_type_filter == type}>
                      {String.capitalize(String.replace(type, "_", " "))}
                    </option>
                  <% end %>
                </select>
              </.form>
            </div>
          </div>
          <%= if @search_query != "" or @item_type_filter != "" do %>
            <div class="flex items-center gap-2 text-xs" style="color: var(--color-quill);">
              <span>Active filters:</span>
              <%= if @search_query != "" do %>
                <span
                  class="px-2 py-1 rounded-full"
                  style="background: rgba(155,126,200,0.12); color: var(--color-wisteria);"
                >
                  Search: "{@search_query}"
                  <button type="button" phx-click="clear_search" class="ml-1 hover:text-white">
                    &times;
                  </button>
                </span>
              <% end %>
              <%= if @item_type_filter != "" do %>
                <span
                  class="px-2 py-1 rounded-full"
                  style="background: rgba(155,126,200,0.12); color: var(--color-wisteria);"
                >
                  Type: {String.capitalize(String.replace(@item_type_filter, "_", " "))}
                  <button type="button" phx-click="clear_type_filter" class="ml-1 hover:text-white">
                    &times;
                  </button>
                </span>
              <% end %>
              <button type="button" phx-click="clear_all_filters" class="underline hover:text-white">
                Clear all
              </button>
            </div>
          <% end %>
        </div>

        <%!-- Status filter tabs --%>
        <div class="flex gap-2 flex-wrap">
          <.link
            patch={~p"/admin/items"}
            class={[
              "px-3 py-1.5 rounded-lg text-xs font-medium transition-colors",
              if(is_nil(@status_filter), do: "text-white", else: "")
            ]}
          >
            <span
              style={
                if(is_nil(@status_filter),
                  do: "background: var(--color-patchouli); color: white;",
                  else: "background: rgba(155,126,200,0.12); color: var(--color-wisteria);"
                )
              }
              class="px-3 py-1.5 rounded-lg text-xs font-medium"
            >
              All
            </span>
          </.link>
          <%= for status <- @statuses do %>
            <.link patch={~p"/admin/items?status=#{status}"}>
              <span class={[
                "status-badge",
                status,
                if(@status_filter == status, do: "ring-2 ring-offset-1", else: "")
              ]}>
                {status}
              </span>
            </.link>
          <% end %>
        </div>

        <div id="items" phx-update="stream" class="space-y-3">
          <div
            :for={{id, item} <- @streams.items}
            id={id}
            class="kiroku-card p-4 flex items-start gap-4"
          >
            <div class="flex-1 min-w-0 space-y-2">
              <div class="flex items-center gap-2 mb-1 flex-wrap">
                <span class="badge-item-type text-xs">{item.item_type}</span>
                <span class={["status-badge text-xs", to_string(item.status)]}>{item.status}</span>
              </div>
              <p class="font-body text-sm font-medium" style="color: var(--color-lilac);">
                {item.title}
              </p>
              <p class="kiroku-handle text-xs">{item.handle || item.id}</p>

              <%!-- Abstract (truncated) --%>
              <%= if item.abstract do %>
                <% abstract_text = item.abstract

                truncated_abstract =
                  if String.length(abstract_text) > 120 do
                    String.slice(abstract_text, 0, 117) <> "..."
                  else
                    abstract_text
                  end %>
                <p
                  class="text-xs leading-relaxed line-clamp-2"
                  style="color: var(--color-quill);"
                >
                  {truncated_abstract}
                </p>
              <% end %>

              <%!-- Author information --%>
              <%= if item.student_name do %>
                <div class="flex items-center gap-2">
                  <div
                    class="w-6 h-6 rounded-full flex items-center justify-center shrink-0 text-[10px] font-bold"
                    style="background: rgba(123,79,166,0.2); color: var(--color-patchouli);"
                  >
                    {String.first(item.student_name)}
                  </div>
                  <div class="flex-1 min-w-0">
                    <p class="font-medium text-xs truncate" style="color: var(--color-wisteria);">
                      {item.student_name}
                    </p>
                    <%= if item.student_id do %>
                      <p class="font-mono text-[10px] truncate" style="color: var(--color-quill);">
                        NPM: {item.student_id}
                      </p>
                    <% end %>
                  </div>
                </div>
              <% end %>

              <%!-- Academic information --%>
              <div class="flex flex-wrap gap-1.5 text-[10px]" style="color: var(--color-quill);">
                <%= if item.program_study do %>
                  <span class="px-1.5 py-0.5 rounded" style="background: rgba(155,126,200,0.06);">
                    {item.program_study}
                  </span>
                <% end %>
                <%= if item.faculty do %>
                  <span class="px-1.5 py-0.5 rounded" style="background: rgba(155,126,200,0.06);">
                    {item.faculty}
                  </span>
                <% end %>
              </div>

              <%!-- Date information --%>
              <%= if not is_nil(item.date_submitted) or not is_nil(item.published_at) or not is_nil(item.inserted_at) do %>
                <% display_date =
                  cond do
                    not is_nil(item.date_submitted) -> item.date_submitted
                    not is_nil(item.published_at) -> item.published_at
                    not is_nil(item.inserted_at) -> item.inserted_at
                    true -> nil
                  end

                date_label =
                  cond do
                    not is_nil(item.date_submitted) -> "Submitted"
                    not is_nil(item.published_at) -> "Published"
                    not is_nil(item.inserted_at) -> "Created"
                    true -> ""
                  end %>
                <%= if display_date do %>
                  <div class="flex items-center gap-1.5">
                    <.icon
                      name="hero-calendar"
                      class="w-3 h-3 shrink-0"
                      style="color: var(--color-dust);"
                    />
                    <span class="font-mono text-[10px]" style="color: var(--color-dust);">
                      {date_label}: {Calendar.strftime(display_date, "%d %b %Y")}
                    </span>
                  </div>
                <% end %>
              <% end %>
            </div>
            <.link
              navigate={~p"/admin/items/#{item.id}"}
              style="color: var(--color-lavender);"
              class="text-xs hover:text-white transition-colors shrink-0"
            >
              Review →
            </.link>
          </div>
        </div>

        <%!-- Results count --%>
        <p class="text-xs text-center" style="color: var(--color-quill);">
          Showing {@pagination.total_count} item{if @pagination.total_count != 1, do: "s"}
        </p>

        <.pagination
          pagination={@pagination}
          path="/admin/items"
          params={
            %{"status" => @status_filter, "search" => @search_query, "item_type" => @item_type_filter}
          }
        />
      </div>
    </Layouts.admin>
    """
  end

  # ── :new render ────────────────────────────────────────────────────────────

  def render(%{live_action: :new} = assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_user} page_title="New Item">
      <div class="max-w-3xl mx-auto space-y-6">
        <div>
          <.link
            patch={~p"/admin/items"}
            class="text-sm transition-colors hover:text-white"
            style="color: var(--color-lavender);"
          >
            ← Back to Items
          </.link>
          <h1 class="font-heading text-3xl mt-2" style="color: var(--color-lilac);">New Item</h1>
          <p class="text-sm mt-1" style="color: var(--color-quill);">
            Create an item on behalf of a submitter or directly for the repository.
          </p>
        </div>

        <.form for={@form} id="item-form" phx-submit="save" phx-change="validate" class="space-y-6">
          <%!-- 1. Identity & type --%>
          <.identity_section form={@form} collections={@collections} />

          <%!-- 2. Abstract --%>
          <.abstract_section form={@form} />

          <%!-- 3. Contributor info — academic / thesis types only --%>
          <.contributor_section :if={academic_type?(@selected_type)} form={@form} />

          <%!-- 4. Type-specific detail fields --%>
          <.type_section type={@selected_type} form={@form} />

          <%!-- 5. Admin: initial status & access --%>
          <div id="admin-settings-section" class="kiroku-card p-6 space-y-4">
            <div
              class="flex items-center gap-3 pb-4 mb-1 border-b"
              style="border-color: rgba(155,126,200,0.15);"
            >
              <div
                class="w-9 h-9 rounded-xl flex items-center justify-center shrink-0"
                style="background: color-mix(in srgb, var(--color-patchouli) 14%, transparent); color: var(--color-patchouli);"
              >
                <.icon name="hero-cog-6-tooth" class="w-5 h-5" />
              </div>
              <div>
                <p
                  class="font-heading font-semibold text-base leading-tight"
                  style="color: var(--color-wisteria);"
                >
                  Pengaturan Admin
                </p>
                <p class="text-xs leading-tight mt-0.5" style="color: var(--color-quill);">
                  Status awal dan hak akses item
                </p>
              </div>
            </div>

            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <div>
                <label class="block text-sm font-medium mb-1.5" style="color: var(--color-wisteria);">
                  Status Awal
                </label>
                <select name="item[status]" id="item-status-select" class="kiroku-search-input w-full">
                  <option value="draft" selected={to_string(@form[:status].value) == "draft"}>
                    Draft
                  </option>
                  <option value="submitted" selected={to_string(@form[:status].value) == "submitted"}>
                    Submitted
                  </option>
                  <option value="published" selected={to_string(@form[:status].value) == "published"}>
                    Published
                  </option>
                </select>
                <p class="text-xs mt-1" style="color: var(--color-quill);">
                  Pilih <em>Published</em> untuk langsung menayangkan.
                </p>
              </div>
              <div>
                <label class="block text-sm font-medium mb-1.5" style="color: var(--color-wisteria);">
                  Hak Akses
                </label>
                <select
                  name="item[access_level]"
                  id="item-access-select"
                  class="kiroku-search-input w-full"
                >
                  <option value="open" selected={to_string(@form[:access_level].value) == "open"}>
                    Open Access
                  </option>
                  <option
                    value="restricted"
                    selected={to_string(@form[:access_level].value) == "restricted"}
                  >
                    Terbatas (Login)
                  </option>
                  <option
                    value="embargoed"
                    selected={to_string(@form[:access_level].value) == "embargoed"}
                  >
                    Embargo
                  </option>
                </select>
              </div>
            </div>

            <.input
              field={@form[:embargo_lift_date]}
              type="date"
              label="Tanggal Berakhir Embargo (jika berlaku)"
            />
          </div>

          <%!-- 6. Actions --%>
          <div class="kiroku-card p-5 flex flex-wrap items-center gap-3">
            <button
              type="submit"
              class="inline-flex items-center gap-2 px-5 py-2.5 rounded-lg font-semibold text-sm transition-all hover:brightness-110 active:scale-95"
              style="background: var(--color-patchouli); color: white; box-shadow: 0 2px 8px rgba(123,79,166,0.35);"
            >
              <.icon name="hero-arrow-down-tray" class="size-4" /> Buat Item
            </button>
            <.link
              patch={~p"/admin/items"}
              class="px-5 py-2.5 rounded-lg font-medium text-sm"
              style="background: rgba(155,126,200,0.1); color: var(--color-wisteria);"
            >
              Batal
            </.link>
          </div>
        </.form>
      </div>
    </Layouts.admin>
    """
  end

  # ── Lifecycle ──────────────────────────────────────────────────────────────

  def mount(_params, _session, socket) do
    collections = list_all_collections()

    {:ok,
     socket
     |> assign(:status_filter, nil)
     |> assign(:search_query, "")
     |> assign(:item_type_filter, "")
     |> assign(:statuses, @statuses)
     |> assign(:item_types, @item_types)
     |> assign(:collections, collections)
     |> assign(:selected_type, "skripsi")
     |> assign(:form, nil)
     |> assign(:search_form, to_form(%{}))
     |> assign(:filter_form, to_form(%{}))
     |> stream(:items, [])}
  end

  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, params) do
    status_filter = Map.get(params, "status")
    search_query = Map.get(params, "search", "")
    item_type_filter = Map.get(params, "item_type", "")
    page = String.to_integer(Map.get(params, "page", "1"))

    filters =
      %{}
      |> maybe_put_status(status_filter)
      |> maybe_put_search(search_query)
      |> maybe_put_item_type(item_type_filter)

    {items, pagination} =
      Repository.list_items_for_display_pagination(filters, page: page, per_page: 15)

    socket
    |> assign(:status_filter, status_filter)
    |> assign(:search_query, search_query)
    |> assign(:item_type_filter, item_type_filter)
    |> assign(:pagination, pagination)
    |> assign(:page_title, "Items")
    |> stream(:items, items, reset: true)
  end

  defp apply_action(socket, :new, _params) do
    changeset = Item.changeset(%Item{}, %{item_type: :skripsi})

    socket
    |> assign(:page_title, "New Item")
    |> assign(:selected_type, "skripsi")
    |> assign(:form, to_form(changeset, as: :item))
  end

  # ── Events ─────────────────────────────────────────────────────────────────

  def handle_event("type_changed", %{"item" => %{"item_type" => type}}, socket) do
    {:noreply, assign(socket, :selected_type, type)}
  end

  def handle_event("search", %{"search" => search}, socket) do
    params = build_index_params(search: search, socket: socket)
    {:noreply, push_patch(socket, to: ~p"/admin/items?#{params}")}
  end

  def handle_event("filter", %{"item_type" => item_type}, socket) do
    params = build_index_params(item_type: item_type, socket: socket)
    {:noreply, push_patch(socket, to: ~p"/admin/items?#{params}")}
  end

  def handle_event("clear_search", _, socket) do
    params = build_index_params(socket: socket)
    {:noreply, push_patch(socket, to: ~p"/admin/items?#{params}")}
  end

  def handle_event("clear_type_filter", _, socket) do
    params = build_index_params(socket: socket, item_type: "")
    {:noreply, push_patch(socket, to: ~p"/admin/items?#{params}")}
  end

  def handle_event("clear_all_filters", _, socket) do
    {:noreply, push_patch(socket, to: ~p"/admin/items")}
  end

  def handle_event("validate", %{"item" => params}, socket) do
    changeset =
      %Item{}
      |> Item.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:selected_type, params["item_type"] || socket.assigns.selected_type)
     |> assign(:form, to_form(changeset, as: :item))}
  end

  def handle_event("save", %{"item" => params}, socket) do
    user = socket.assigns.current_user
    attrs = Map.put(params, "submitter_id", user.id)

    case Repository.create_item(attrs) do
      {:ok, _item} ->
        {:noreply,
         socket
         |> put_flash(:info, "Item created successfully.")
         |> push_patch(to: ~p"/admin/items")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :item))}
    end
  end

  # ── Helpers ────────────────────────────────────────────────────────────────

  defp list_all_collections do
    Repository.list_collections()
    |> Enum.filter(& &1.is_active)
  end

  defp maybe_put_status(filters, nil), do: filters
  defp maybe_put_status(filters, status), do: Map.put(filters, :status, status)

  defp maybe_put_search(filters, ""), do: filters
  defp maybe_put_search(filters, search), do: Map.put(filters, :search, search)

  defp maybe_put_item_type(filters, ""), do: filters
  defp maybe_put_item_type(filters, item_type), do: Map.put(filters, :item_type, item_type)

  # Builds a query-params map for push_patch, filtering out nil/empty values
  # so Phoenix's verified route encoder never receives nil.
  defp build_index_params(opts) do
    socket = Keyword.fetch!(opts, :socket)
    search = Keyword.get(opts, :search, socket.assigns.search_query)
    item_type = Keyword.get(opts, :item_type, socket.assigns.item_type_filter)
    status = socket.assigns.status_filter

    %{}
    |> then(fn m -> if search not in [nil, ""], do: Map.put(m, "search", search), else: m end)
    |> then(fn m -> if item_type not in [nil, ""], do: Map.put(m, "item_type", item_type), else: m end)
    |> then(fn m -> if status not in [nil, ""], do: Map.put(m, "status", status), else: m end)
  end
end
