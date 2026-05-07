defmodule KirokuWeb.Admin.ItemLive.Index do
  use KirokuWeb, :live_view

  import KirokuWeb.ItemForm

  alias Kiroku.Repository
  alias Kiroku.Repository.Item

  @statuses ~w(submitted published draft embargoed withdrawn)

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

        <div id="items" phx-update="stream" class="space-y-2">
          <div
            :for={{id, item} <- @streams.items}
            id={id}
            class="kiroku-card p-4 flex items-start gap-4"
          >
            <div class="flex-1 min-w-0">
              <div class="flex items-center gap-2 mb-1 flex-wrap">
                <span class="badge-item-type">{item.item_type}</span>
                <span class={["status-badge", to_string(item.status)]}>{item.status}</span>
              </div>
              <p class="font-body text-sm" style="color: var(--color-lilac);">{item.title}</p>
              <p class="kiroku-handle text-xs mt-0.5">{item.handle || item.id}</p>
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
     |> assign(:statuses, @statuses)
     |> assign(:collections, collections)
     |> assign(:selected_type, "skripsi")
     |> assign(:form, nil)
     |> stream(:items, Repository.list_items(%{}))}
  end

  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, %{"status" => status}) do
    items = Repository.list_items(%{status: status})

    socket
    |> assign(:status_filter, status)
    |> assign(:page_title, "Items")
    |> stream(:items, items, reset: true)
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:status_filter, nil)
    |> assign(:page_title, "Items")
    |> stream(:items, Repository.list_items(%{}), reset: true)
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
    Repository.list_communities()
    |> Enum.flat_map(fn community ->
      Repository.list_collections_for_community(community.id)
    end)
  end
end
