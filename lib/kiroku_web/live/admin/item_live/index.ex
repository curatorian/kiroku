defmodule KirokuWeb.Admin.ItemLive.Index do
  use KirokuWeb, :live_view

  alias Kiroku.Repository

  @statuses ~w(submitted published draft embargoed withdrawn)

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_user}>
      <div class="space-y-6">
        <div class="flex items-center justify-between">
          <h1 class="font-heading text-3xl" style="color: var(--color-lilac);">Items</h1>
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
    </Layouts.app>
    """
  end

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:status_filter, nil)
     |> assign(:statuses, @statuses)
     |> stream(:items, Repository.list_items(%{}))}
  end

  def handle_params(params, _uri, socket) do
    status = params["status"]
    items = Repository.list_items(%{status: status})

    {:noreply,
     socket
     |> assign(:status_filter, status)
     |> stream(:items, items, reset: true)}
  end
end
