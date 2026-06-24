defmodule KirokuWeb.Admin.ItemLive.Show do
  use KirokuWeb, :live_view

  alias Kiroku.Repository

  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_user} page_title="Items">
      <div class="max-w-4xl mx-auto space-y-6">
        <div class="flex items-center gap-4">
          <.link
            navigate={~p"/admin/items"}
            style="color: var(--color-lavender);"
            class="text-sm hover:text-white transition-colors"
          >
            ← Items
          </.link>
          <span class="badge-item-type">{@item.item_type}</span>
          <span class={["status-badge", to_string(@item.status)]}>{@item.status}</span>
        </div>

        <div class="kiroku-card p-6 space-y-4">
          <h1 class="font-heading text-2xl" style="color: var(--color-lilac);">{@item.title}</h1>
          <p class="kiroku-handle">{@item.handle || @item.id}</p>

          <%= if @item.abstract do %>
            <div>
              <p class="text-xs font-medium mb-1" style="color: var(--color-wisteria);">Abstract</p>
              <p class="text-sm leading-relaxed" style="color: var(--color-quill);">
                {@item.abstract}
              </p>
            </div>
          <% end %>

          <div class="grid grid-cols-2 gap-4 text-sm pt-2" style="color: var(--color-quill);">
            <%= if @item.publication_year do %>
              <div>
                <span class="font-medium" style="color: var(--color-wisteria);">Year:</span> {@item.publication_year}
              </div>
            <% end %>
            <%= if @item.faculty do %>
              <div>
                <span class="font-medium" style="color: var(--color-wisteria);">Faculty:</span> {@item.faculty}
              </div>
            <% end %>
          </div>
        </div>

        <%!-- Actions --%>
        <div class="kiroku-card p-5 space-y-3">
          <h3 class="font-heading text-lg" style="color: var(--color-lilac);">Actions</h3>
          <div class="flex flex-wrap gap-3">
            <%= if @item.status in [:submitted, :draft] do %>
              <button
                phx-click="publish"
                data-confirm="Publish this item?"
                class="px-4 py-2 rounded-lg text-sm font-medium"
                style="background: rgba(90,158,114,0.15); color: #5A9E72; border: 1px solid rgba(90,158,114,0.3);"
              >
                Publish
              </button>
            <% end %>
            <%= if @item.status == :published do %>
              <button
                phx-click="withdraw"
                data-confirm="Withdraw this item?"
                class="px-4 py-2 rounded-lg text-sm font-medium"
                style="background: rgba(196,65,90,0.12); color: var(--color-ribbon-red); border: 1px solid rgba(196,65,90,0.2);"
              >
                Withdraw
              </button>
            <% end %>
            <%= if @item.status == :embargoed do %>
              <button
                phx-click="lift_embargo"
                data-confirm="Lift the embargo on this item?"
                class="px-4 py-2 rounded-lg text-sm font-medium"
                style="background: rgba(212,160,23,0.15); color: var(--color-ribbon-gold); border: 1px solid rgba(212,160,23,0.3);"
              >
                Lift Embargo
              </button>
            <% end %>
            <button
              phx-click="delete"
              data-confirm="Permanently delete this item?"
              class="px-4 py-2 rounded-lg text-sm font-medium"
              style="background: rgba(196,65,90,0.08); color: var(--color-ribbon-red); border: 1px solid rgba(196,65,90,0.15);"
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
    item = Repository.get_item_with_preloads!(id)
    {:ok, assign(socket, :item, item)}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  def handle_event("publish", _params, socket) do
    case Repository.publish_item(socket.assigns.item) do
      {:ok, item} ->
        {:noreply, socket |> put_flash(:info, "Item published.") |> assign(:item, item)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to publish item.")}
    end
  end

  def handle_event("withdraw", _params, socket) do
    case Repository.withdraw_item_fsm(socket.assigns.item) do
      {:ok, item} ->
        {:noreply, socket |> put_flash(:info, "Item withdrawn.") |> assign(:item, item)}

      {:error, :invalid_transition} ->
        {:noreply, put_flash(socket, :error, "Cannot withdraw from current status.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to withdraw item.")}
    end
  end

  def handle_event("lift_embargo", _params, socket) do
    case Repository.lift_embargo(socket.assigns.item) do
      {:ok, item} ->
        {:noreply, socket |> put_flash(:info, "Embargo lifted.") |> assign(:item, item)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to lift embargo.")}
    end
  end

  def handle_event("delete", _params, socket) do
    {:ok, _} = Repository.delete_item(socket.assigns.item)

    {:noreply,
     socket
     |> put_flash(:info, "Item deleted.")
     |> push_navigate(to: ~p"/admin/items")}
  end
end
