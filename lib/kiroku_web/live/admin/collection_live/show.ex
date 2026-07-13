defmodule KirokuWeb.Admin.CollectionLive.Show do
  use KirokuWeb, :live_view

  alias Kiroku.Repository

  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_user} page_title="Collections">
      <div class="max-w-2xl mx-auto space-y-6">
        <div class="flex items-center gap-4">
          <.link
            navigate={~p"/admin/collections"}
            style="color: var(--color-lavender);"
            class="text-sm hover:text-white transition-colors"
          >
            ← Collections
          </.link>
          <h1 class="font-heading text-2xl" style="color: var(--color-lilac);">{@collection.name}</h1>
          <span class="kiroku-handle">{@collection.handle}</span>
        </div>
        <div class="kiroku-card p-6 space-y-4">
          <div class="flex items-center gap-2 flex-wrap">
            <%= if @collection.is_active do %>
              <span class="status-badge published">Active</span>
            <% else %>
              <span class="status-badge withdrawn">Inactive</span>
            <% end %>
            <span class="status-badge submitted">Visibility: {@collection.access_level}</span>
            <span class="status-badge draft">
              New items default to: {@collection.default_item_access_level}
            </span>
          </div>
          <%= if @collection.short_description do %>
            <p style="color: var(--color-quill);">{@collection.short_description}</p>
          <% end %>
          <div class="flex gap-3 pt-2">
            <.link
              patch={~p"/admin/collections/#{@collection.id}/edit"}
              class="px-4 py-2 rounded-lg text-sm font-medium"
              style="background: rgba(155,126,200,0.12); color: var(--color-wisteria); border: 1px solid rgba(155,126,200,0.2);"
            >
              Edit
            </.link>
            <button
              phx-click="delete"
              data-confirm="Delete this collection?"
              class="px-4 py-2 rounded-lg text-sm font-medium"
              style="background: rgba(196,65,90,0.12); color: var(--color-ribbon-red); border: 1px solid rgba(196,65,90,0.2);"
            >
              Delete
            </button>
          </div>
        </div>
      </div>
    </Layouts.admin>
    """
  end

  def mount(%{"id" => id}, _session, socket) do
    collection = Repository.get_collection!(id)
    {:ok, assign(socket, :collection, collection)}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  def handle_event("delete", _params, socket) do
    {:ok, _} = Repository.delete_collection(socket.assigns.collection)

    {:noreply,
     socket
     |> put_flash(:info, "Collection deleted.")
     |> push_navigate(to: ~p"/admin/collections")}
  end
end
