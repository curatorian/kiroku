defmodule KirokuWeb.Admin.UserLive.Index do
  use KirokuWeb, :live_view

  alias Kiroku.Accounts

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_user}>
      <div class="space-y-6">
        <h1 class="font-heading text-3xl" style="color: var(--color-lilac);">Users</h1>
        <div class="kiroku-card overflow-hidden">
          <table class="w-full text-sm">
            <thead style="background: rgba(45,27,105,0.5);">
              <tr>
                <th class="px-4 py-3 text-left font-medium" style="color: var(--color-wisteria);">
                  Email
                </th>
                <th class="px-4 py-3 text-left font-medium" style="color: var(--color-wisteria);">
                  Name
                </th>
                <th class="px-4 py-3 text-left font-medium" style="color: var(--color-wisteria);">
                  Role
                </th>
                <th class="px-4 py-3 text-left font-medium" style="color: var(--color-wisteria);">
                  Confirmed
                </th>
                <th class="px-4 py-3"></th>
              </tr>
            </thead>
            <tbody id="users" phx-update="stream">
              <tr
                :for={{id, user} <- @streams.users}
                id={id}
                style="border-top: 1px solid rgba(155,126,200,0.1);"
              >
                <td class="px-4 py-3" style="color: var(--color-lilac);">{user.email}</td>
                <td class="px-4 py-3" style="color: var(--color-quill);">{user.display_name}</td>
                <td class="px-4 py-3">
                  <span class="badge-item-type">{user.user_type}</span>
                </td>
                <td class="px-4 py-3" style="color: var(--color-quill);">
                  <%= if user.confirmed_at do %>
                    <span class="status-badge published">Yes</span>
                  <% else %>
                    <span class="status-badge draft">No</span>
                  <% end %>
                </td>
                <td class="px-4 py-3 text-right">
                  <.link
                    navigate={~p"/admin/users/#{user.id}"}
                    style="color: var(--color-lavender);"
                    class="text-xs hover:text-white transition-colors"
                  >
                    View
                  </.link>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </Layouts.app>
    """
  end

  def mount(_params, _session, socket) do
    users = Accounts.list_users()
    {:ok, stream(socket, :users, users)}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}
end
