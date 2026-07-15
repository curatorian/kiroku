defmodule KirokuWeb.Admin.UserLive.Show do
  use KirokuWeb, :live_view

  alias Kiroku.Accounts
  alias Kiroku.Accounts.User
  alias Kiroku.Access.{RbacPolicies, RbacPolicy}

  @user_types_all ~w(submitter internal reviewer admin superadmin)
  @user_types_limited ~w(submitter internal reviewer)

  # ── Render ───────────────────────────────────────────────────────────────────

  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_user} page_title="Users">
      <div class="max-w-3xl mx-auto space-y-6">
        <%!-- Breadcrumb --%>
        <div class="flex items-center gap-3 text-sm">
          <.link
            navigate={~p"/admin/users"}
            style="color: var(--color-lavender);"
            class="hover:text-white transition-colors"
          >
            Users
          </.link>
          <span style="color: var(--color-dust);">/</span>
          <span style="color: var(--color-lilac);">{@user.email}</span>
        </div>

        <%!-- Profile card --%>
        <div class="kiroku-card p-6">
          <div class="flex items-start justify-between gap-4">
            <div class="flex items-center gap-4">
              <div
                class="w-14 h-14 rounded-full flex items-center justify-center text-xl font-bold flex-shrink-0"
                style="background: rgba(123,79,166,0.25); color: var(--color-lavender);"
              >
                {String.first(@user.display_name || @user.email) |> String.upcase()}
              </div>
              <div>
                <h1 class="font-heading text-xl" style="color: var(--color-lilac);">
                  {@user.display_name || "—"}
                </h1>
                <p class="text-sm" style="color: var(--color-dust);">{@user.email}</p>
                <div class="flex items-center gap-2 mt-2">
                  <span class={["status-badge", role_badge_class(@user.user_type)]}>
                    {@user.user_type}
                  </span>
                  <%= if @user.confirmed_at do %>
                    <span class="status-badge published">Confirmed</span>
                  <% else %>
                    <span class="status-badge draft">Unconfirmed</span>
                  <% end %>
                </div>
              </div>
            </div>
            <div class="flex gap-2 flex-shrink-0">
              <%= if can_edit_user?(@current_user, @user) do %>
                <.link
                  patch={~p"/admin/users/#{@user.id}/edit"}
                  class="px-3 py-2 rounded-lg text-xs font-medium"
                  style="background: rgba(155,126,200,0.12); color: var(--color-wisteria); border: 1px solid rgba(155,126,200,0.2);"
                >
                  Edit
                </.link>
                <.link
                  patch={~p"/admin/users/#{@user.id}/password"}
                  class="px-3 py-2 rounded-lg text-xs font-medium"
                  style="background: rgba(155,126,200,0.12); color: var(--color-wisteria); border: 1px solid rgba(155,126,200,0.2);"
                >
                  Set Password
                </.link>
              <% end %>
              <%= if @current_user.user_type == :superadmin do %>
                <.link
                  navigate={~p"/admin/users/#{@user.id}/role-management"}
                  class="px-3 py-2 rounded-lg text-xs font-medium"
                  style="background: rgba(16,185,129,0.15); color: #6ee7b7; border: 1px solid rgba(16,185,129,0.25);"
                >
                  Area Access
                </.link>
              <% end %>
            </div>
          </div>

          <div class="grid grid-cols-2 gap-x-8 gap-y-3 mt-6 text-sm">
            <%= if @user.identifier do %>
              <div>
                <span class="text-xs uppercase tracking-wide" style="color: var(--color-wisteria);">
                  Identifier
                </span>
                <p style="color: var(--color-lilac);">{@user.identifier}</p>
              </div>
            <% end %>
            <%= if @user.faculty do %>
              <div>
                <span class="text-xs uppercase tracking-wide" style="color: var(--color-wisteria);">
                  Faculty
                </span>
                <p style="color: var(--color-lilac);">{@user.faculty}</p>
              </div>
            <% end %>
            <%= if @user.department do %>
              <div>
                <span class="text-xs uppercase tracking-wide" style="color: var(--color-wisteria);">
                  Department
                </span>
                <p style="color: var(--color-lilac);">{@user.department}</p>
              </div>
            <% end %>
            <div>
              <span class="text-xs uppercase tracking-wide" style="color: var(--color-wisteria);">
                Joined
              </span>
              <p style="color: var(--color-lilac);">
                {Calendar.strftime(@user.inserted_at, "%d %B %Y")}
              </p>
            </div>
          </div>
        </div>

        <%!-- RBAC Policies --%>
        <div class="kiroku-card overflow-hidden">
          <div
            class="px-5 py-4 flex items-center justify-between"
            style="border-bottom: 1px solid rgba(155,126,200,0.1);"
          >
            <h2 class="font-semibold text-sm" style="color: var(--color-lilac);">Access Policies</h2>
            <%= if @current_user.user_type == :superadmin do %>
              <.link
                patch={~p"/admin/users/#{@user.id}/policies/new"}
                class="flex items-center gap-1.5 text-xs px-3 py-1.5 rounded-lg font-medium"
                style="background: rgba(155,126,200,0.12); color: var(--color-wisteria);"
              >
                <.icon name="hero-plus" class="size-3.5" /> Add Policy
              </.link>
            <% end %>
          </div>
          <div
            class="divide-y"
            style="--tw-divide-opacity: 0.08; border-color: rgba(155,126,200,0.08);"
          >
            <%= if @policies == [] do %>
              <p class="px-5 py-6 text-sm text-center" style="color: var(--color-dust);">
                No custom policies. Default role permissions apply.
              </p>
            <% else %>
              <div
                :for={policy <- @policies}
                class="px-5 py-3 flex items-center justify-between gap-4 hover:bg-base-300/20 transition-colors"
              >
                <div class="flex items-center gap-3 text-sm">
                  <span class="status-badge under-review">{policy.resource_type}</span>
                  <span style="color: var(--color-wisteria);">→</span>
                  <span class="status-badge published">{policy.action}</span>
                  <%= if policy.resource_id do %>
                    <span class="text-xs font-mono" style="color: var(--color-dust);">
                      {String.slice(policy.resource_id, 0, 8)}…
                    </span>
                  <% else %>
                    <span class="text-xs" style="color: var(--color-dust);">(global)</span>
                  <% end %>
                  <%= if policy.notes do %>
                    <span class="text-xs italic" style="color: var(--color-dust);">
                      {policy.notes}
                    </span>
                  <% end %>
                </div>
                <%= if @current_user.user_type == :superadmin do %>
                  <div class="flex items-center gap-3">
                    <.link
                      patch={~p"/admin/users/#{@user.id}/policies/#{policy.id}/edit"}
                      class="text-xs transition-colors hover:text-white"
                      style="color: var(--color-lavender);"
                    >
                      Edit
                    </.link>
                    <button
                      phx-click="delete_policy"
                      phx-value-id={policy.id}
                      data-confirm="Delete this policy?"
                      class="text-xs transition-colors hover:text-red-400"
                      style="color: var(--color-ribbon-red);"
                    >
                      Delete
                    </button>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>
      </div>

      <%!-- Edit user modal --%>
      <%= if @live_action == :edit do %>
        <.modal_shell title={"Edit — #{@user.email}"} close={~p"/admin/users/#{@user.id}"}>
          <.form
            for={@form}
            id="edit-user-form"
            phx-submit="save_edit"
            phx-change="validate_edit"
            class="space-y-4"
          >
            <.input field={@form[:email]} type="email" label="Email" />
            <.input field={@form[:display_name]} type="text" label="Display Name" />
            <.input field={@form[:identifier]} type="text" label="Identifier" />
            <.input field={@form[:faculty]} type="text" label="Faculty" />
            <.input field={@form[:department]} type="text" label="Department" />
            <%= if can_change_role?(@current_user, @user) do %>
              <.input
                field={@form[:user_type]}
                type="select"
                label="Role"
                options={role_options_for(@current_user)}
              />
            <% end %>
            <.modal_actions save_label="Save" cancel={~p"/admin/users/#{@user.id}"} />
          </.form>
        </.modal_shell>
      <% end %>

      <%!-- Password modal --%>
      <%= if @live_action == :password do %>
        <.modal_shell title={"Set Password — #{@user.email}"} close={~p"/admin/users/#{@user.id}"}>
          <.form
            for={@pw_form}
            id="password-form"
            phx-submit="save_password"
            phx-change="validate_password"
            class="space-y-4"
          >
            <.input field={@pw_form[:password]} type="password" label="New Password" required />
            <.input
              field={@pw_form[:password_confirmation]}
              type="password"
              label="Confirm Password"
              required
            />
            <.modal_actions save_label="Update Password" cancel={~p"/admin/users/#{@user.id}"} />
          </.form>
        </.modal_shell>
      <% end %>

      <%!-- New policy modal --%>
      <%= if @live_action == :new_policy do %>
        <.modal_shell title="Add Access Policy" close={~p"/admin/users/#{@user.id}"}>
          <.form
            for={@policy_form}
            id="policy-form"
            phx-submit="save_policy"
            phx-change="validate_policy"
            class="space-y-4"
          >
            <.input
              field={@policy_form[:resource_type]}
              type="select"
              label="Resource Type"
              options={[
                {"Community", "community"},
                {"Collection", "collection"},
                {"Item", "item"},
                {"Global", "global"}
              ]}
            />
            <.input
              field={@policy_form[:resource_id]}
              type="text"
              label="Resource ID (leave blank for global)"
            />
            <.input
              field={@policy_form[:action]}
              type="select"
              label="Action"
              options={[
                {"Read", "read"},
                {"Submit", "submit"},
                {"Review", "review"},
                {"Publish", "publish"},
                {"Manage", "manage"}
              ]}
            />
            <.input field={@policy_form[:notes]} type="text" label="Notes (optional)" />
            <.modal_actions save_label="Add Policy" cancel={~p"/admin/users/#{@user.id}"} />
          </.form>
        </.modal_shell>
      <% end %>

      <%!-- Edit policy modal --%>
      <%= if @live_action == :edit_policy do %>
        <.modal_shell title="Edit Access Policy" close={~p"/admin/users/#{@user.id}"}>
          <.form
            for={@policy_form}
            id="edit-policy-form"
            phx-submit="update_policy"
            phx-change="validate_policy"
            class="space-y-4"
          >
            <.input
              field={@policy_form[:resource_type]}
              type="select"
              label="Resource Type"
              options={[
                {"Community", "community"},
                {"Collection", "collection"},
                {"Item", "item"},
                {"Global", "global"}
              ]}
            />
            <.input
              field={@policy_form[:resource_id]}
              type="text"
              label="Resource ID (leave blank for global)"
            />
            <.input
              field={@policy_form[:action]}
              type="select"
              label="Action"
              options={[
                {"Read", "read"},
                {"Submit", "submit"},
                {"Review", "review"},
                {"Publish", "publish"},
                {"Manage", "manage"}
              ]}
            />
            <.input field={@policy_form[:notes]} type="text" label="Notes (optional)" />
            <.modal_actions save_label="Update Policy" cancel={~p"/admin/users/#{@user.id}"} />
          </.form>
        </.modal_shell>
      <% end %>
    </Layouts.admin>
    """
  end

  # ── Sub-components ────────────────────────────────────────────────────────────

  attr :title, :string, required: true
  attr :close, :string, required: true
  slot :inner_block, required: true

  defp modal_shell(assigns) do
    ~H"""
    <div
      id="modal-overlay"
      class="fixed inset-0 z-50 flex items-center justify-center p-4"
      style="background: rgba(0,0,0,0.6);"
    >
      <div class="kiroku-card p-6 w-full max-w-lg space-y-5">
        <div class="flex items-center justify-between">
          <h2 class="font-heading text-xl" style="color: var(--color-lilac);">{@title}</h2>
          <.link patch={@close} class="opacity-50 hover:opacity-100 transition-opacity">
            <.icon name="hero-x-mark" class="size-5" />
          </.link>
        </div>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  attr :save_label, :string, default: "Save"
  attr :cancel, :string, required: true

  defp modal_actions(assigns) do
    ~H"""
    <div class="flex gap-3 pt-2">
      <button
        type="submit"
        class="px-5 py-2.5 rounded-lg font-semibold text-sm"
        style="background: var(--color-patchouli); color: white;"
      >
        {@save_label}
      </button>
      <.link
        patch={@cancel}
        class="px-5 py-2.5 rounded-lg font-medium text-sm"
        style="background: rgba(155,126,200,0.1); color: var(--color-wisteria);"
      >
        Cancel
      </.link>
    </div>
    """
  end

  # ── Mount & params ─────────────────────────────────────────────────────────────

  def mount(%{"id" => id}, _session, socket) do
    user = Accounts.get_user!(id)
    policies = RbacPolicies.list_policies_for_user(user.id)

    {:ok,
     socket
     |> assign(:user, user)
     |> assign(:policies, policies)
     |> assign(:form, nil)
     |> assign(:pw_form, nil)
     |> assign(:policy_form, nil)
     |> assign(:editing_policy, nil)}
  end

  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :show, _params) do
    socket
    |> assign(:form, nil)
    |> assign(:pw_form, nil)
    |> assign(:policy_form, nil)
  end

  defp apply_action(socket, :edit, _params) do
    user = socket.assigns.user
    form = to_form(User.admin_changeset(user, %{}), as: :user)
    assign(socket, :form, form)
  end

  defp apply_action(socket, :password, _params) do
    pw_form = to_form(User.admin_set_password_changeset(socket.assigns.user, %{}), as: :user)
    assign(socket, :pw_form, pw_form)
  end

  defp apply_action(socket, :new_policy, _params) do
    changeset = RbacPolicies.change_policy(%RbacPolicy{}, %{})
    assign(socket, :policy_form, to_form(changeset, as: :policy))
  end

  defp apply_action(socket, :edit_policy, %{"policy_id" => policy_id}) do
    policy = RbacPolicies.get_policy!(policy_id)
    changeset = RbacPolicies.change_policy(policy, %{})

    socket
    |> assign(:editing_policy, policy)
    |> assign(:policy_form, to_form(changeset, as: :policy))
  end

  defp apply_action(socket, _action, _params), do: socket

  # ── Events ────────────────────────────────────────────────────────────────────

  def handle_event("validate_edit", %{"user" => params}, socket) do
    changeset =
      socket.assigns.user
      |> User.admin_changeset(params, validate_email: false)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: :user))}
  end

  def handle_event("save_edit", %{"user" => params}, socket) do
    user = socket.assigns.user
    current_user = socket.assigns.current_user

    if can_edit_user?(current_user, user) do
      params = maybe_restrict_role(params, current_user)

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
    else
      {:noreply, put_flash(socket, :error, "Permission denied.")}
    end
  end

  def handle_event("validate_password", %{"user" => params}, socket) do
    changeset =
      socket.assigns.user
      |> User.admin_set_password_changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :pw_form, to_form(changeset, as: :user))}
  end

  def handle_event("save_password", %{"user" => params}, socket) do
    user = socket.assigns.user
    current_user = socket.assigns.current_user

    if can_edit_user?(current_user, user) do
      case Accounts.admin_set_password(user, params) do
        {:ok, _user} ->
          {:noreply,
           socket
           |> put_flash(:info, "Password updated.")
           |> push_patch(to: ~p"/admin/users/#{user.id}")}

        {:error, changeset} ->
          {:noreply, assign(socket, :pw_form, to_form(changeset, as: :user))}
      end
    else
      {:noreply, put_flash(socket, :error, "Permission denied.")}
    end
  end

  def handle_event("validate_policy", %{"policy" => params}, socket) do
    policy = socket.assigns.editing_policy || %RbacPolicy{}
    changeset = RbacPolicies.change_policy(policy, params) |> Map.put(:action, :validate)
    {:noreply, assign(socket, :policy_form, to_form(changeset, as: :policy))}
  end

  def handle_event("save_policy", %{"policy" => params}, socket) do
    user = socket.assigns.user
    params = Map.put(params, "user_id", user.id)

    case RbacPolicies.create_policy(params) do
      {:ok, _policy} ->
        policies = RbacPolicies.list_policies_for_user(user.id)

        {:noreply,
         socket
         |> put_flash(:info, "Policy added.")
         |> assign(:policies, policies)
         |> push_patch(to: ~p"/admin/users/#{user.id}")}

      {:error, changeset} ->
        {:noreply, assign(socket, :policy_form, to_form(changeset, as: :policy))}
    end
  end

  def handle_event("update_policy", %{"policy" => params}, socket) do
    policy = socket.assigns.editing_policy

    case RbacPolicies.update_policy(policy, params) do
      {:ok, _policy} ->
        user = socket.assigns.user
        policies = RbacPolicies.list_policies_for_user(user.id)

        {:noreply,
         socket
         |> put_flash(:info, "Policy updated.")
         |> assign(:policies, policies)
         |> push_patch(to: ~p"/admin/users/#{user.id}")}

      {:error, changeset} ->
        {:noreply, assign(socket, :policy_form, to_form(changeset, as: :policy))}
    end
  end

  def handle_event("delete_policy", %{"id" => id}, socket) do
    if socket.assigns.current_user.user_type == :superadmin do
      policy = RbacPolicies.get_policy!(id)
      {:ok, _} = RbacPolicies.delete_policy(policy)
      user = socket.assigns.user
      policies = RbacPolicies.list_policies_for_user(user.id)

      {:noreply,
       socket
       |> put_flash(:info, "Policy deleted.")
       |> assign(:policies, policies)}
    else
      {:noreply, put_flash(socket, :error, "Permission denied.")}
    end
  end

  # ── Permission helpers ─────────────────────────────────────────────────────────

  defp can_edit_user?(%{user_type: :superadmin}, _target), do: true

  defp can_edit_user?(%{user_type: :admin}, %{user_type: type})
       when type in [:reviewer, :submitter],
       do: true

  defp can_edit_user?(_actor, _target), do: false

  defp can_change_role?(%{user_type: :superadmin}, _target), do: true

  defp can_change_role?(%{user_type: :admin}, %{user_type: type})
       when type in [:reviewer, :submitter],
       do: true

  defp can_change_role?(_actor, _target), do: false

  defp role_options_for(%{user_type: :superadmin}) do
    Enum.map(@user_types_all, &{String.capitalize(&1), &1})
  end

  defp role_options_for(%{user_type: :admin}) do
    Enum.map(@user_types_limited, &{String.capitalize(&1), &1})
  end

  defp role_options_for(_), do: []

  # Prevent admins from promoting users to admin/superadmin
  defp maybe_restrict_role(params, %{user_type: :admin}) do
    user_type = Map.get(params, "user_type", "submitter")

    if user_type in @user_types_limited do
      params
    else
      Map.put(params, "user_type", "submitter")
    end
  end

  defp maybe_restrict_role(params, _current_user), do: params

  defp role_badge_class(:superadmin), do: "submitted"
  defp role_badge_class(:admin), do: "under-review"
  defp role_badge_class(:reviewer), do: "embargoed"
  defp role_badge_class(:internal), do: "published"
  defp role_badge_class(:submitter), do: "draft"
  defp role_badge_class(_), do: "draft"
end
