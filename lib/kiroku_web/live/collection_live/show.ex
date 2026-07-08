defmodule KirokuWeb.CollectionLive.Show do
  use KirokuWeb, :live_view

  import KirokuWeb.KirokuPublicComponents
  import KirokuWeb.KirokuComponents

  alias Kiroku.Repository
  alias Kiroku.Pagination

  @impl true
  def mount(%{"handle" => handle}, _session, socket) do
    collection = Repository.get_collection_by_handle!(handle)
    collection = Kiroku.Repo.preload(collection, :community)
    item_count = Repository.count_items_for_collection(collection.id)
    ancestor_chain = Repository.community_ancestor_chain(collection.community_id)

    {:ok,
     socket
     |> assign(:page_title, "#{collection.name} — Kiroku")
     |> assign(:collection, collection)
     |> assign(:item_count, item_count)
     |> assign(:ancestor_chain, ancestor_chain)
     |> assign(:items, [])
     |> assign(:pagination, Pagination.build(item_count, 1, 20))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    collection = socket.assigns.collection
    page = parse_page(params["page"])

    {items, pagination} =
      Repository.list_items_for_collection_pagination(collection.id, page: page, per_page: 20)

    {:noreply,
     socket
     |> assign(:items, items)
     |> assign(:pagination, pagination)}
  end

  defp parse_page(nil), do: 1

  defp parse_page(p) do
    case Integer.parse(p) do
      {n, ""} when n > 0 -> n
      _ -> 1
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

        <%!-- Items list --%>
        <div>
          <h2 class="font-heading text-2xl mb-4" style="color: var(--color-lilac);">Items</h2>
          <%= if @items == [] do %>
            <div class="kiroku-card p-8 text-center">
              <p style="color: var(--color-quill);">
                No published items in this collection yet.
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
              path="/collections/#{@collection.handle}"
              params={%{}}
            />
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
