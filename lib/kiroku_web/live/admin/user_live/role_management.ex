defmodule KirokuWeb.Admin.UserLive.RoleManagement do
  @moduledoc """
  Enhanced role management interface for super admins to manage area-based permissions.

  Provides a visual interface for granting users access to specific communities and collections
  with different permission levels (read, manage, etc.).
  """

  use KirokuWeb, :live_view

  alias Kiroku.Accounts
  alias Kiroku.Access.RbacPolicies
  alias Kiroku.Repository.{Community, Collection}
  alias Kiroku.Repo
  import Ecto.Query

  @permission_levels [
    {"No Access", ""},
    {"Read Only", "read"},
    {"Submit Items", "submit"},
    {"Review & Publish", "review"},
    {"Full Management", "manage"}
  ]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_user} page_title="Role Management">
      <div class="max-w-6xl mx-auto space-y-6">
        <%!-- Header --%>
        <div class="flex items-center justify-between">
          <div>
            <h1 class="font-heading text-2xl" style="color: var(--color-lilac);">
              Area Access Management
            </h1>
            <p class="text-sm mt-1" style="color: var(--color-dust);">
              Manage which communities and collections {@user.email} can access
            </p>
          </div>
          <.link
            navigate={~p"/admin/users/#{@user.id}"}
            class="px-4 py-2 rounded-lg text-sm font-medium"
            style="background: rgba(155,126,200,0.12); color: var(--color-wisteria);"
          >
            Back to User
          </.link>
        </div>

        <%!-- User info card --%>
        <div class="kiroku-card p-4 flex items-center gap-4">
          <div
            class="w-12 h-12 rounded-full flex items-center justify-center text-lg font-bold flex-shrink-0"
            style="background: rgba(123,79,166,0.25); color: var(--color-lavender);"
          >
            {String.first(@user.display_name || @user.email) |> String.upcase()}
          </div>
          <div class="flex-1">
            <h3 class="font-semibold" style="color: var(--color-lilac);">
              {@user.display_name || "—"}
            </h3>
            <p class="text-sm" style="color: var(--color-dust);">{@user.email}</p>
          </div>
          <div class="flex items-center gap-3">
            <span class={["status-badge", role_badge_class(@user.user_type)]}>
              {@user.user_type}
            </span>
            <span class="text-xs" style="color: var(--color-dust);">
              {@total_permissions} permission(s)
            </span>
          </div>
        </div>

        <%!-- Communities & Collections --%>
        <div class="space-y-6">
          <%= for {community, collections} <- @community_structure do %>
            <div class="kiroku-card overflow-hidden">
              <%!-- Community header --%>
              <div
                class="p-4 flex items-center justify-between"
                style="background: rgba(45,27,105,0.2);"
              >
                <div class="flex items-center gap-3">
                  <.icon name="hero-folder" class="size-5" style="color: var(--color-patchouli);" />
                  <div>
                    <h3 class="font-semibold" style="color: var(--color-lilac);">
                      {community.name}
                    </h3>
                    <p class="text-xs" style="color: var(--color-dust);">
                      {community.handle} • {length(collections)} collection(s)
                    </p>
                  </div>
                </div>
                <div class="flex items-center gap-2">
                  <span class="text-xs" style="color: var(--color-dust);">Community Access:</span>
                  <form
                    phx-change="update_community_permission"
                    class="flex items-center gap-2"
                  >
                    <input type="hidden" name="community_id" value={community.id} />
                    <select
                      name="permission_level"
                      class="text-sm py-1 px-2 rounded-lg border border-base-300 focus:outline-none focus:ring-2 focus:ring-purple-500"
                      style="background: rgba(155,126,200,0.08);"
                    >
                      <option value="">No Access</option>
                      <option value="read" selected={@community_permissions[community.id] == "read"}>
                        Read Only
                      </option>
                      <option
                        value="submit"
                        selected={@community_permissions[community.id] == "submit"}
                      >
                        Submit Items
                      </option>
                      <option
                        value="review"
                        selected={@community_permissions[community.id] == "review"}
                      >
                        Review & Publish
                      </option>
                      <option
                        value="manage"
                        selected={@community_permissions[community.id] == "manage"}
                      >
                        Full Management
                      </option>
                    </select>
                  </form>
                </div>
              </div>

              <%!-- Collections --%>
              <div class="divide-y" style="border-color: rgba(155,126,200,0.08);">
                <%= for collection <- collections do %>
                  <div class="p-4 flex items-center justify-between hover:bg-base-300/20 transition-colors">
                    <div class="flex items-center gap-3 flex-1">
                      <.icon
                        name="hero-folder-open"
                        class="size-4"
                        style="color: var(--color-lavender);"
                      />
                      <div>
                        <h4 class="font-medium text-sm" style="color: var(--color-lilac);">
                          {collection.name}
                        </h4>
                        <p class="text-xs" style="color: var(--color-dust);">
                          {collection.handle}
                        </p>
                      </div>
                    </div>
                    <div class="flex items-center gap-2">
                      <span class="text-xs" style="color: var(--color-dust);">Access:</span>
                      <form
                        phx-change="update_collection_permission"
                        class="flex items-center gap-2"
                      >
                        <input type="hidden" name="collection_id" value={collection.id} />
                        <select
                          name="permission_level"
                          class="text-sm py-1 px-2 rounded-lg border border-base-300 focus:outline-none focus:ring-2 focus:ring-purple-500"
                          style="background: rgba(155,126,200,0.08);"
                        >
                          <option value="">No Access</option>
                          <option
                            value="read"
                            selected={@collection_permissions[collection.id] == "read"}
                          >
                            Read Only
                          </option>
                          <option
                            value="submit"
                            selected={@collection_permissions[collection.id] == "submit"}
                          >
                            Submit Items
                          </option>
                          <option
                            value="review"
                            selected={@collection_permissions[collection.id] == "review"}
                          >
                            Review & Publish
                          </option>
                          <option
                            value="manage"
                            selected={@collection_permissions[collection.id] == "manage"}
                          >
                            Full Management
                          </option>
                        </select>
                      </form>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>

        <%!-- Global permissions --%>
        <div class="kiroku-card p-6">
          <h3 class="font-semibold mb-4" style="color: var(--color-lilac);">
            Global Permissions
          </h3>
          <div class="grid md:grid-cols-2 gap-4">
            <div class="p-4 rounded-lg" style="background: rgba(155,126,200,0.05);">
              <h4 class="font-medium text-sm mb-2" style="color: var(--color-wisteria);">
                System-wide Access
              </h4>
              <div class="space-y-2">
                <%= for {action, label} <- [
                  {"read", "Read all content"},
                  {"submit", "Submit anywhere"},
                  {"review", "Review anywhere"},
                  {"publish", "Publish anywhere"},
                  {"manage", "Full system management"}
                ] do %>
                  <label class="flex items-center gap-2 cursor-pointer">
                    <input
                      type="checkbox"
                      checked={has_global_permission?(@global_policies, action)}
                      phx-click="toggle_global_permission"
                      phx-value-action={action}
                      class="h-4 w-4 rounded"
                      style="accent-color: var(--color-patchouli);"
                    />
                    <span class="text-sm" style="color: var(--color-lilac);">
                      {label}
                    </span>
                  </label>
                <% end %>
              </div>
            </div>
          </div>
        </div>

        <%!-- Quick actions --%>
        <div class="kiroku-card p-6">
          <h3 class="font-semibold mb-4" style="color: var(--color-lilac);">
            Quick Actions
          </h3>
          <div class="flex flex-wrap gap-3">
            <button
              phx-click="grant_all_read"
              class="px-4 py-2 rounded-lg text-sm font-medium"
              style="background: rgba(16,185,129,0.15); color: #6ee7b7; border: 1px solid rgba(16,185,129,0.25);"
            >
              Grant Read Access to All
            </button>
            <button
              phx-click="revoke_all_permissions"
              class="px-4 py-2 rounded-lg text-sm font-medium"
              style="background: rgba(239,68,68,0.15); color: #fca5a5; border: 1px solid rgba(239,68,68,0.25);"
            >
              Revoke All Custom Permissions
            </button>
          </div>
        </div>
      </div>
    </Layouts.admin>
    """
  end

  @impl true
  def mount(%{"id" => user_id}, _session, socket) do
    current_user = socket.assigns.current_user

    if current_user.user_type != :superadmin do
      {:ok,
       socket
       |> put_flash(:error, "Only super admins can manage role permissions.")
       |> push_navigate(to: ~p"/admin/users")}
    else
      user = Accounts.get_user!(user_id)
      community_structure = load_community_structure()
      community_permissions = build_community_permissions(user.id, community_structure)
      collection_permissions = build_collection_permissions(user.id, community_structure)
      global_policies = load_global_policies(user.id)
      total_permissions = count_total_permissions(user.id)

      {:ok,
       socket
       |> assign(:user, user)
       |> assign(:community_structure, community_structure)
       |> assign(:community_permissions, community_permissions)
       |> assign(:collection_permissions, collection_permissions)
       |> assign(:global_policies, global_policies)
       |> assign(:permission_levels, @permission_levels)
       |> assign(:total_permissions, total_permissions)}
    end
  end

  @impl true
  def handle_event(
        "update_community_permission",
        %{"community_id" => community_id, "permission_level" => level},
        socket
      ) do
    user_id = socket.assigns.user.id

    case level do
      "" ->
        RbacPolicies.revoke_area_access(user_id, "community", community_id)

      action ->
        RbacPolicies.grant_area_access(user_id, "community", community_id, action)
    end

    community_structure = socket.assigns.community_structure
    community_permissions = build_community_permissions(user_id, community_structure)
    total_permissions = count_total_permissions(user_id)

    {:noreply,
     socket
     |> assign(:community_permissions, community_permissions)
     |> assign(:total_permissions, total_permissions)
     |> put_flash(:info, "Community permission updated.")}
  end

  def handle_event(
        "update_collection_permission",
        %{"collection_id" => collection_id, "permission_level" => level},
        socket
      ) do
    user_id = socket.assigns.user.id

    case level do
      "" ->
        RbacPolicies.revoke_area_access(user_id, "collection", collection_id)

      action ->
        RbacPolicies.grant_area_access(user_id, "collection", collection_id, action)
    end

    community_structure = socket.assigns.community_structure
    collection_permissions = build_collection_permissions(user_id, community_structure)
    total_permissions = count_total_permissions(user_id)

    {:noreply,
     socket
     |> assign(:collection_permissions, collection_permissions)
     |> assign(:total_permissions, total_permissions)
     |> put_flash(:info, "Collection permission updated.")}
  end

  def handle_event("toggle_global_permission", %{"action" => action}, socket) do
    user_id = socket.assigns.user.id
    current_policies = socket.assigns.global_policies

    if action in current_policies do
      policy = get_global_policy(user_id, action)
      if policy, do: RbacPolicies.delete_policy(policy)

      new_global_policies = List.delete(current_policies, action)
      total_permissions = socket.assigns.total_permissions - 1

      {:noreply,
       socket
       |> assign(:global_policies, new_global_policies)
       |> assign(:total_permissions, total_permissions)
       |> put_flash(:info, "Global #{action} permission revoked.")}
    else
      case RbacPolicies.create_policy(%{
             "user_id" => user_id,
             "resource_type" => "global",
             "resource_id" => nil,
             "action" => action,
             "notes" => "Granted via role management"
           }) do
        {:ok, _policy} ->
          new_global_policies = [action | current_policies]
          total_permissions = socket.assigns.total_permissions + 1

          {:noreply,
           socket
           |> assign(:global_policies, new_global_policies)
           |> assign(:total_permissions, total_permissions)
           |> put_flash(:info, "Global #{action} permission granted.")}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to grant permission.")}
      end
    end
  end

  def handle_event("grant_all_read", _, socket) do
    user_id = socket.assigns.user.id
    community_structure = socket.assigns.community_structure

    Enum.each(community_structure, fn {community, collections} ->
      create_policy_if_not_exists(user_id, "community", community.id, "read")

      Enum.each(collections, fn collection ->
        create_policy_if_not_exists(user_id, "collection", collection.id, "read")
      end)
    end)

    community_structure = load_community_structure()
    community_permissions = build_community_permissions(user_id, community_structure)
    collection_permissions = build_collection_permissions(user_id, community_structure)
    total_permissions = count_total_permissions(user_id)

    {:noreply,
     socket
     |> assign(:community_structure, community_structure)
     |> assign(:community_permissions, community_permissions)
     |> assign(:collection_permissions, collection_permissions)
     |> assign(:total_permissions, total_permissions)
     |> put_flash(:info, "Read access granted to all communities and collections.")}
  end

  def handle_event("revoke_all_permissions", _, socket) do
    user_id = socket.assigns.user.id

    RbacPolicies.bulk_delete_user_policies(user_id)

    community_structure = load_community_structure()
    community_permissions = build_community_permissions(user_id, community_structure)
    collection_permissions = build_collection_permissions(user_id, community_structure)
    global_policies = []
    total_permissions = 0

    {:noreply,
     socket
     |> assign(:community_structure, community_structure)
     |> assign(:community_permissions, community_permissions)
     |> assign(:collection_permissions, collection_permissions)
     |> assign(:global_policies, global_policies)
     |> assign(:total_permissions, total_permissions)
     |> put_flash(:info, "All custom permissions revoked.")}
  end

  # ── Data loading helpers ──

  defp load_community_structure do
    communities =
      Repo.all(
        from c in Community,
          where: c.is_active == true,
          order_by: [asc: c.position, asc: c.name]
      )

    Enum.map(communities, fn community ->
      collections =
        Repo.all(
          from coll in Collection,
            where: coll.community_id == ^community.id and coll.is_active == true,
            order_by: [asc: coll.position, asc: coll.name]
        )

      {community, collections}
    end)
  end

  defp load_global_policies(user_id) do
    RbacPolicies.list_policies_for_user(user_id)
    |> Enum.filter(&(&1.resource_type == :global))
    |> Enum.map(&Atom.to_string(&1.action))
  end

  defp build_community_permissions(user_id, community_structure) do
    community_policies =
      RbacPolicies.list_policies_for_user(user_id)
      |> Enum.filter(&(&1.resource_type == :community))
      |> Map.new(fn policy -> {policy.resource_id, Atom.to_string(policy.action)} end)

    Enum.into(community_structure, %{}, fn {community, _collections} ->
      {community.id, Map.get(community_policies, community.id, "")}
    end)
  end

  defp build_collection_permissions(user_id, community_structure) do
    collection_policies =
      RbacPolicies.list_policies_for_user(user_id)
      |> Enum.filter(&(&1.resource_type == :collection))
      |> Map.new(fn policy -> {policy.resource_id, Atom.to_string(policy.action)} end)

    Enum.reduce(community_structure, %{}, fn {_community, collections}, acc ->
      Enum.reduce(collections, acc, fn collection, inner_acc ->
        Map.put(inner_acc, collection.id, Map.get(collection_policies, collection.id, ""))
      end)
    end)
  end

  defp count_total_permissions(user_id) do
    length(RbacPolicies.list_policies_for_user(user_id))
  end

  defp get_global_policy(user_id, action) do
    action_atom = String.to_existing_atom(action)

    RbacPolicies.list_policies_for_user(user_id)
    |> Enum.find(fn policy ->
      policy.resource_type == :global and policy.action == action_atom
    end)
  rescue
    ArgumentError -> nil
  end

  defp create_policy_if_not_exists(user_id, resource_type, resource_id, action) do
    case RbacPolicies.get_user_policy_for_resource(user_id, resource_type, resource_id) do
      nil ->
        RbacPolicies.create_policy(%{
          "user_id" => user_id,
          "resource_type" => resource_type,
          "resource_id" => resource_id,
          "action" => action,
          "notes" => "Granted via role management"
        })

      _existing ->
        :ok
    end
  end

  defp has_global_permission?(global_policies, action) do
    action in global_policies
  end

  defp role_badge_class(:superadmin), do: "submitted"
  defp role_badge_class(:admin), do: "under-review"
  defp role_badge_class(:reviewer), do: "embargoed"
  defp role_badge_class(:submitter), do: "draft"
  defp role_badge_class(_), do: "draft"
end
