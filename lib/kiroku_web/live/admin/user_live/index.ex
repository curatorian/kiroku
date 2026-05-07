defmodule KirokuWeb.Admin.UserLive.Index do
  use KirokuWeb, :live_view

  alias Kiroku.Accounts
  alias Kiroku.Accounts.User

  @user_types_all ~w(submitter reviewer admin superadmin)
  @user_types_admin ~w(submitter reviewer)

  # ── Render ──────────────────────────────────────────────────────────────────

  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_user} page_title="Users">
      <div class="space-y-6">
        <%!-- Header --%>
        <div class="flex items-center justify-between">
          <div>
            <h1 class="font-heading text-2xl" style="color: var(--color-lilac);">Users</h1>
            <p class="text-sm mt-0.5" style="color: var(--color-dust);">
              {@total_users} total users
            </p>
          </div>
          <%= if can_create_user?(@current_user) do %>
            <.link
              patch={~p"/admin/users/new"}
              class="flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-semibold"
              style="background: var(--color-patchouli); color: white;"
            >
              <.icon name="hero-plus" class="size-4" /> New User
            </.link>
          <% end %>
        </div>

        <%!-- Filter tabs --%>
        <div class="flex gap-2 flex-wrap">
          <.link
            patch={~p"/admin/users"}
            class={[
              "px-3 py-1.5 rounded-lg text-xs font-medium transition-colors",
              (@filter == "all" && "text-white") || "hover:bg-base-300"
            ]}
            style={
              if @filter == "all",
                do: "background: var(--color-patchouli);",
                else: "color: var(--color-dust);"
            }
          >
            All
          </.link>
          <%= for type <- @available_types do %>
            <.link
              patch={~p"/admin/users?type=#{type}"}
              class={[
                "px-3 py-1.5 rounded-lg text-xs font-medium transition-colors",
                (@filter == type && "text-white") || "hover:bg-base-300"
              ]}
              style={
                if @filter == type,
                  do: "background: var(--color-patchouli);",
                  else: "color: var(--color-dust);"
              }
            >
              {String.capitalize(type)}
            </.link>
          <% end %>
        </div>

        <%!-- User table --%>
        <div class="kiroku-card overflow-hidden">
          <table class="w-full text-sm">
            <thead style="background: rgba(45,27,105,0.4);">
              <tr>
                <th
                  class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider"
                  style="color: var(--color-wisteria);"
                >
                  User
                </th>
                <th
                  class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider"
                  style="color: var(--color-wisteria);"
                >
                  Role
                </th>
                <th
                  class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider"
                  style="color: var(--color-wisteria);"
                >
                  Confirmed
                </th>
                <th
                  class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider"
                  style="color: var(--color-wisteria);"
                >
                  Joined
                </th>
                <th class="px-4 py-3"></th>
              </tr>
            </thead>
            <tbody id="users" phx-update="stream">
              <tr
                :for={{id, user} <- @streams.users}
                id={id}
                class="transition-colors hover:bg-base-300/30"
                style="border-top: 1px solid rgba(155,126,200,0.08);"
              >
                <td class="px-4 py-3">
                  <div class="flex items-center gap-3">
                    <div
                      class="w-8 h-8 rounded-full flex items-center justify-center text-sm font-bold flex-shrink-0"
                      style="background: rgba(123,79,166,0.25); color: var(--color-lavender);"
                    >
                      {String.first(user.display_name || user.email) |> String.upcase()}
                    </div>
                    <div>
                      <p class="font-medium" style="color: var(--color-lilac);">
                        {user.display_name || "—"}
                      </p>
                      <p class="text-xs" style="color: var(--color-dust);">{user.email}</p>
                    </div>
                  </div>
                </td>
                <td class="px-4 py-3">
                  <span class={["status-badge", role_badge_class(user.user_type)]}>
                    {user.user_type}
                  </span>
                </td>
                <td class="px-4 py-3">
                  <%= if user.confirmed_at do %>
                    <span class="status-badge published">Confirmed</span>
                  <% else %>
                    <span class="status-badge draft">Pending</span>
                  <% end %>
                </td>
                <td class="px-4 py-3 text-xs" style="color: var(--color-dust);">
                  {Calendar.strftime(user.inserted_at, "%d %b %Y")}
                </td>
                <td class="px-4 py-3">
                  <div class="flex items-center justify-end gap-3">
                    <.link
                      navigate={~p"/admin/users/#{user.id}"}
                      class="text-xs transition-colors hover:text-white"
                      style="color: var(--color-lavender);"
                    >
                      View
                    </.link>
                    <%= if can_delete_user?(@current_user, user) do %>
                      <button
                        phx-click="delete_user"
                        phx-value-id={user.id}
                        data-confirm={"Delete #{user.email}? This cannot be undone."}
                        class="text-xs transition-colors hover:text-red-400"
                        style="color: var(--color-ribbon-red);"
                      >
                        Delete
                      </button>
                    <% end %>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <%!-- New User Modal --%>
      <%= if @live_action == :new do %>
        <div
          id="new-user-modal"
          class="fixed inset-0 z-50 flex items-center justify-center p-4"
          style="background: rgba(0,0,0,0.6);"
        >
          <div class="kiroku-card p-6 w-full max-w-lg space-y-5">
            <div class="flex items-center justify-between">
              <h2 class="font-heading text-xl" style="color: var(--color-lilac);">Create User</h2>
              <.link patch={~p"/admin/users"} class="opacity-50 hover:opacity-100 transition-opacity">
                <.icon name="hero-x-mark" class="size-5" />
              </.link>
            </div>
            <.form
              for={@form}
              id="new-user-form"
              phx-submit="create_user"
              phx-change="validate_user"
              class="space-y-4"
            >
              <.input field={@form[:email]} type="email" label="Email" required />
              <.input field={@form[:display_name]} type="text" label="Display Name" required />
              <.input field={@form[:password]} type="password" label="Password" required />
              <.input
                field={@form[:password_confirmation]}
                type="password"
                label="Confirm Password"
                required
              />
              <.input
                field={@form[:user_type]}
                type="select"
                label="Role"
                options={role_options_for(@current_user)}
              />
              <div class="flex gap-3 pt-2">
                <button
                  type="submit"
                  class="px-5 py-2.5 rounded-lg font-semibold text-sm"
                  style="background: var(--color-patchouli); color: white;"
                >
                  Create
                </button>
                <.link
                  patch={~p"/admin/users"}
                  class="px-5 py-2.5 rounded-lg font-medium text-sm"
                  style="background: rgba(155,126,200,0.1); color: var(--color-wisteria);"
                >
                  Cancel
                </.link>
              </div>
            </.form>
          </div>
        </div>
      <% end %>
    </Layouts.admin>
    """
  end

  # ── Mount & params ───────────────────────────────────────────────────────────

  def mount(_params, _session, socket) do
    users = Accounts.list_users_with_policies()

    {:ok,
     socket
     |> assign(:total_users, length(users))
     |> assign(:filter, "all")
     |> assign(:available_types, available_types_for(socket.assigns.current_user))
     |> assign(:form, nil)
     |> stream(:users, users)}
  end

  def handle_params(params, _uri, socket) do
    filter = Map.get(params, "type", "all")
    users = filtered_users(filter)

    socket =
      socket
      |> assign(:filter, filter)
      |> stream(:users, users, reset: true)
      |> apply_action(socket.assigns.live_action, params)

    {:noreply, socket}
  end

  defp apply_action(socket, :new, _params) do
    changeset = Accounts.change_user_registration(%User{})
    assign(socket, :form, to_form(changeset, as: :user))
  end

  defp apply_action(socket, _action, _params), do: socket

  # ── Events ───────────────────────────────────────────────────────────────────

  def handle_event("validate_user", %{"user" => params}, socket) do
    changeset =
      %User{}
      |> User.admin_changeset(params, validate_email: false)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: :user))}
  end

  def handle_event("create_user", %{"user" => params}, socket) do
    case Accounts.admin_create_user(params) do
      {:ok, user} ->
        {:noreply,
         socket
         |> put_flash(:info, "User #{user.email} created.")
         |> stream_insert(:users, user, at: 0)
         |> assign(:total_users, socket.assigns.total_users + 1)
         |> push_patch(to: ~p"/admin/users")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :user))}
    end
  end

  def handle_event("delete_user", %{"id" => id}, socket) do
    user = Accounts.get_user!(id)

    if can_delete_user?(socket.assigns.current_user, user) do
      {:ok, _} = Accounts.delete_user(user)

      {:noreply,
       socket
       |> put_flash(:info, "User #{user.email} deleted.")
       |> stream_delete(:users, user)
       |> assign(:total_users, socket.assigns.total_users - 1)}
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to delete this user.")}
    end
  end

  # ── Permission helpers ───────────────────────────────────────────────────────

  defp can_create_user?(%{user_type: type}) when type in [:admin, :superadmin], do: true
  defp can_create_user?(_), do: false

  defp can_delete_user?(%{user_type: :superadmin}, _target), do: true
  defp can_delete_user?(_actor, _target), do: false

  defp available_types_for(%{user_type: :superadmin}), do: @user_types_all
  defp available_types_for(%{user_type: :admin}), do: @user_types_admin
  defp available_types_for(_), do: []

  defp role_options_for(%{user_type: :superadmin}) do
    Enum.map(@user_types_all, &{String.capitalize(&1), &1})
  end

  defp role_options_for(%{user_type: :admin}) do
    Enum.map(@user_types_admin, &{String.capitalize(&1), &1})
  end

  defp role_options_for(_), do: []

  defp filtered_users("all"), do: Accounts.list_users_with_policies()

  defp filtered_users(type) when type in @user_types_all do
    import Ecto.Query

    Kiroku.Repo.all(
      from u in User,
        where: u.user_type == ^String.to_existing_atom(type),
        order_by: [asc: u.email]
    )
  end

  defp filtered_users(_), do: Accounts.list_users_with_policies()

  defp role_badge_class(:superadmin), do: "submitted"
  defp role_badge_class(:admin), do: "under-review"
  defp role_badge_class(:reviewer), do: "embargoed"
  defp role_badge_class(:submitter), do: "draft"
  defp role_badge_class(_), do: "draft"
end
