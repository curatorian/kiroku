defmodule KirokuWeb.Admin.UserLive.Show do
  use KirokuWeb, :live_view

  alias Kiroku.Accounts
  alias Kiroku.Accounts.User

  @user_types ~w(submitter reviewer admin superadmin)

  def render(%{live_action: :show} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_user}>
      <div class="max-w-2xl mx-auto space-y-6">
        <div class="flex items-center gap-4">
          <.link
            navigate={~p"/admin/users"}
            style="color: var(--color-lavender);"
            class="text-sm hover:text-white transition-colors"
          >
            ← Users
          </.link>
          <h1 class="font-heading text-2xl" style="color: var(--color-lilac);">{@user.email}</h1>
        </div>
        <div class="kiroku-card p-6 space-y-4">
          <div class="grid grid-cols-2 gap-4 text-sm">
            <div style="color: var(--color-quill);">
              <span class="font-medium" style="color: var(--color-wisteria);">Name:</span>
              {@user.display_name}
            </div>
            <div style="color: var(--color-quill);">
              <span class="font-medium" style="color: var(--color-wisteria);">Role:</span>
              {@user.user_type}
            </div>
            <div style="color: var(--color-quill);">
              <span class="font-medium" style="color: var(--color-wisteria);">Confirmed:</span>
              {if @user.confirmed_at, do: "Yes", else: "No"}
            </div>
          </div>
          <.link
            patch={~p"/admin/users/#{@user.id}/edit"}
            class="inline-block px-4 py-2 rounded-lg text-sm font-medium"
            style="background: rgba(155,126,200,0.12); color: var(--color-wisteria); border: 1px solid rgba(155,126,200,0.2);"
          >
            Edit Role
          </.link>
        </div>
      </div>
    </Layouts.app>
    """
  end

  def render(%{live_action: :edit} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_user}>
      <div class="max-w-2xl mx-auto space-y-6">
        <div class="flex items-center gap-4">
          <.link
            navigate={~p"/admin/users/#{@user.id}"}
            style="color: var(--color-lavender);"
            class="text-sm hover:text-white transition-colors"
          >
            ← {@user.email}
          </.link>
          <h1 class="font-heading text-2xl" style="color: var(--color-lilac);">Edit User</h1>
        </div>
        <div class="kiroku-card p-6">
          <.form for={@form} id="user-form" phx-submit="save" class="space-y-4">
            <div>
              <label class="block text-sm font-medium mb-1.5" style="color: var(--color-wisteria);">
                Role
              </label>
              <select name="user[user_type]" class="kiroku-search-input">
                <%= for type <- @user_types do %>
                  <option value={type} selected={to_string(@user.user_type) == type}>
                    {String.capitalize(type)}
                  </option>
                <% end %>
              </select>
            </div>
            <.input field={@form[:display_name]} type="text" label="Display Name" />
            <div class="flex gap-3 pt-2">
              <button
                type="submit"
                class="px-5 py-2.5 rounded-lg font-semibold text-sm"
                style="background: var(--color-patchouli); color: white;"
              >
                Save
              </button>
              <.link
                navigate={~p"/admin/users/#{@user.id}"}
                class="px-5 py-2.5 rounded-lg font-medium text-sm"
                style="background: rgba(155,126,200,0.1); color: var(--color-wisteria);"
              >
                Cancel
              </.link>
            </div>
          </.form>
        </div>
      </div>
    </Layouts.app>
    """
  end

  def mount(%{"id" => id}, _session, socket) do
    user = Accounts.get_user!(id)
    {:ok, socket |> assign(:user, user) |> assign(:user_types, @user_types)}
  end

  def handle_params(_params, _uri, socket) do
    user = socket.assigns.user
    form = to_form(User.profile_changeset(user, %{}), as: :user)
    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("save", %{"user" => params}, socket) do
    user = socket.assigns.user

    case Accounts.admin_update_user(user, params) do
      {:ok, updated_user} ->
        {:noreply,
         socket
         |> put_flash(:info, "User updated.")
         |> assign(:user, updated_user)
         |> push_patch(to: ~p"/admin/users/#{user.id}")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :user))}
    end
  end
end
