defmodule KirokuWeb.Admin.CommunityLive.Show do
  use KirokuWeb, :live_view

  alias Kiroku.Repository

  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_user} page_title="Communities">
      <div class="max-w-2xl mx-auto space-y-6">
        <div class="flex items-center gap-4">
          <.link
            navigate={~p"/admin/communities"}
            style="color: var(--color-lavender);"
            class="text-sm hover:text-white transition-colors"
          >
            ← Communities
          </.link>
          <h1 class="font-heading text-2xl" style="color: var(--color-lilac);">{@community.name}</h1>
          <span class="kiroku-handle">{@community.handle}</span>
        </div>

        <div :if={@community.parent_community} class="text-sm" style="color: var(--color-quill);">
          Part of
          <.link
            navigate={~p"/admin/communities/#{@community.parent_community.id}"}
            style="color: var(--color-lavender);"
            class="hover:text-white transition-colors"
          >
            {@community.parent_community.name}
          </.link>
        </div>

        <div class="kiroku-card p-6 space-y-4">
          <div class="flex items-center gap-2 flex-wrap">
            <%= if @community.is_active do %>
              <span class="status-badge published">Active</span>
            <% else %>
              <span class="status-badge withdrawn">Inactive</span>
            <% end %>
            <span class="status-badge submitted">Visibility: {@community.access_level}</span>
          </div>
          <%= if @community.short_description do %>
            <p style="color: var(--color-quill);">{@community.short_description}</p>
          <% end %>
          <%= if @community.description do %>
            <p class="text-sm leading-relaxed" style="color: var(--color-quill);">
              {@community.description}
            </p>
          <% end %>
          <div class="flex gap-3 pt-2">
            <.link
              patch={~p"/admin/communities/#{@community.id}/edit"}
              class="px-4 py-2 rounded-lg text-sm font-medium"
              style="background: rgba(155,126,200,0.12); color: var(--color-wisteria); border: 1px solid rgba(155,126,200,0.2);"
            >
              Edit
            </.link>
            <button
              phx-click="delete"
              data-confirm="Delete this community? Its subcommunities will become top-level."
              class="px-4 py-2 rounded-lg text-sm font-medium"
              style="background: rgba(196,65,90,0.12); color: var(--color-ribbon-red); border: 1px solid rgba(196,65,90,0.2);"
            >
              Delete
            </button>
          </div>
        </div>

        <div :if={@community.subcommunities != []} class="kiroku-card p-6">
          <h2 class="font-heading text-lg mb-3" style="color: var(--color-lilac);">
            Subcommunities
          </h2>
          <ul class="space-y-2">
            <li :for={sub <- @community.subcommunities} class="flex items-center gap-2">
              <span style="color: var(--color-wisteria);">
                <.icon name="hero-folder" class="w-4 h-4" />
              </span>
              <.link
                navigate={~p"/admin/communities/#{sub.id}"}
                style="color: var(--color-lavender);"
                class="hover:text-white transition-colors text-sm"
              >
                {sub.name}
              </.link>
              <span class="kiroku-handle text-xs">/{sub.handle}</span>
            </li>
          </ul>
        </div>
      </div>
    </Layouts.admin>
    """
  end

  def mount(%{"id" => id}, _session, socket) do
    if superadmin?(socket) do
      community = Repository.get_community_with_relations!(id, scope: :staff)
      {:ok, assign(socket, :community, community)}
    else
      {:ok,
       socket
       |> put_flash(:error, "Only superadmins can manage communities.")
       |> push_navigate(to: ~p"/admin")}
    end
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  def handle_event("delete", _params, socket) do
    {:ok, _} = Repository.delete_community(socket.assigns.community)

    {:noreply,
     socket
     |> put_flash(:info, "Community deleted.")
     |> push_navigate(to: ~p"/admin/communities")}
  end

  defp superadmin?(socket) do
    socket.assigns[:current_user] && socket.assigns.current_user.user_type == :superadmin
  end
end
