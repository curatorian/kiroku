defmodule KirokuWeb.Admin.RolePolicyLive do
  use KirokuWeb, :live_view

  alias Kiroku.Access.{RolePolicies, RolePolicy}

  @role_labels %{
    submitter: "Submitter",
    internal: "Internal",
    reviewer: "Reviewer",
    admin: "Admin"
  }

  @action_labels %{
    read: "Read",
    submit: "Submit",
    review: "Review",
    publish: "Publish",
    manage: "Manage (all)"
  }

  @resource_labels %{
    global: "Global (all resources)",
    community: "Community",
    collection: "Collection",
    item: "Item"
  }

  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_user} page_title="Role Policy">
      <div class="space-y-6 max-w-4xl mx-auto">
        <div class="flex items-center justify-between">
          <div>
            <h1 class="font-heading text-2xl" style="color: var(--color-lilac);">Role Policies</h1>
            <p class="text-sm mt-0.5" style="color: var(--color-dust);">
              Apply access policies to entire roles — affects every user with that role.
            </p>
          </div>
          <button
            phx-click="new_policy"
            class="flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-semibold"
            style="background: var(--color-patchouli); color: white;"
          >
            <.icon name="hero-plus" class="size-4" /> Add Policy
          </button>
        </div>

        <%= if @policies == [] do %>
          <div class="kiroku-card p-8 text-center">
            <.icon name="hero-shield-exclamation" class="w-10 h-10 mx-auto opacity-30" />
            <p class="mt-3 text-sm" style="color: var(--color-quill);">
              No role policies yet. Default role rules apply.
            </p>
          </div>
        <% else %>
          <%= for {role, label} <- Map.to_list(@role_labels) do %>
            <% role_policies = Enum.filter(@policies, &(&1.user_type == role)) %>
            <%= if role_policies != [] do %>
              <div class="kiroku-card overflow-hidden">
                <div
                  class="px-5 py-4 flex items-center gap-2"
                  style="border-bottom: 1px solid rgba(155,126,200,0.1);"
                >
                  <.icon
                    name="hero-user-group"
                    class="w-5 h-5"
                    style="color: var(--color-patchouli);"
                  />
                  <h2 class="font-semibold text-sm" style="color: var(--color-lilac);">{label}</h2>
                  <span class="text-xs" style="color: var(--color-dust);">
                    ({length(role_policies)} polic{if length(role_policies) == 1, do: "y", else: "ies"})
                  </span>
                </div>
                <div class="divide-y" style="border-color: rgba(155,126,200,0.08);">
                  <div
                    :for={policy <- role_policies}
                    class="px-5 py-3 flex items-center justify-between gap-4 hover:bg-base-300/20 transition-colors"
                  >
                    <div class="flex items-center gap-3 text-sm min-w-0">
                      <span class="status-badge under-review shrink-0">
                        {@resource_labels[policy.resource_type]}
                      </span>
                      <span style="color: var(--color-wisteria);">→</span>
                      <span class="status-badge published shrink-0">
                        {@action_labels[policy.action]}
                      </span>
                      <%= if policy.resource_id do %>
                        <span class="text-xs font-mono truncate" style="color: var(--color-dust);">
                          {String.slice(policy.resource_id, 0, 8)}…
                        </span>
                      <% else %>
                        <span class="text-xs" style="color: var(--color-dust);">(all)</span>
                      <% end %>
                      <%= if policy.notes do %>
                        <span class="text-xs italic truncate" style="color: var(--color-dust);">
                          {policy.notes}
                        </span>
                      <% end %>
                    </div>
                    <div class="flex items-center gap-3 shrink-0">
                      <button
                        phx-click="edit_policy"
                        phx-value-id={policy.id}
                        class="text-xs transition-colors hover:text-white"
                        style="color: var(--color-lavender);"
                      >
                        Edit
                      </button>
                      <button
                        phx-click="delete_policy"
                        phx-value-id={policy.id}
                        data-confirm="Delete this role policy?"
                        class="text-xs transition-colors hover:text-red-400"
                        style="color: var(--color-ribbon-red);"
                      >
                        Delete
                      </button>
                    </div>
                  </div>
                </div>
              </div>
            <% end %>
          <% end %>
        <% end %>
      </div>

      <%= if @show_modal do %>
        <div
          id="policy-modal"
          class="fixed inset-0 z-50 flex items-center justify-center p-4"
          style="background: rgba(0,0,0,0.6);"
        >
          <div class="kiroku-card p-6 w-full max-w-lg space-y-5">
            <div class="flex items-center justify-between">
              <h2 class="font-heading text-xl" style="color: var(--color-lilac);">
                {if @editing, do: "Edit", else: "Add"} Role Policy
              </h2>
              <button
                phx-click="close_modal"
                class="opacity-50 hover:opacity-100 transition-opacity"
              >
                <.icon name="hero-x-mark" class="size-5" />
              </button>
            </div>
            <.form
              for={@form}
              id="role-policy-form"
              phx-submit="save_policy"
              phx-change="validate_policy"
              class="space-y-4"
            >
              <.input
                field={@form[:user_type]}
                type="select"
                label="Role"
                options={role_options()}
              />
              <.input
                field={@form[:resource_type]}
                type="select"
                label="Resource Type"
                options={resource_options()}
              />
              <.input
                field={@form[:resource_id]}
                type="text"
                label="Resource ID (leave blank for global/all)"
              />
              <.input
                field={@form[:action]}
                type="select"
                label="Action"
                options={action_options()}
              />
              <.input field={@form[:notes]} type="text" label="Notes (optional)" />
              <div class="flex gap-3 pt-2">
                <button
                  type="submit"
                  class="px-5 py-2.5 rounded-lg font-semibold text-sm"
                  style="background: var(--color-patchouli); color: white;"
                >
                  {if @editing, do: "Update", else: "Create"}
                </button>
                <button
                  type="button"
                  phx-click="close_modal"
                  class="px-5 py-2.5 rounded-lg font-medium text-sm"
                  style="background: rgba(155,126,200,0.1); color: var(--color-wisteria);"
                >
                  Cancel
                </button>
              </div>
            </.form>
          </div>
        </div>
      <% end %>
    </Layouts.admin>
    """
  end

  # ── Lifecycle ────────────────────────────────────────────────────────────────

  def mount(_params, _session, socket) do
    if socket.assigns.current_user.user_type != :superadmin do
      {:ok,
       socket
       |> put_flash(:error, "Only superadmins can manage role policies.")
       |> push_navigate(to: ~p"/admin")}
    else
      {:ok,
       socket
       |> assign(:show_modal, false)
       |> assign(:editing, nil)
       |> assign(:form, nil)
       |> assign(:role_labels, @role_labels)
       |> assign(:action_labels, @action_labels)
       |> assign(:resource_labels, @resource_labels)
       |> load_policies()}
    end
  end

  defp load_policies(socket) do
    policies = RolePolicies.list_role_policies()
    assign(socket, :policies, policies)
  end

  # ── Events ───────────────────────────────────────────────────────────────────

  def handle_event("new_policy", _, socket) do
    changeset =
      RolePolicies.change_role_policy(%RolePolicy{}, %{
        user_type: "submitter",
        resource_type: "global",
        action: "read"
      })

    {:noreply,
     socket
     |> assign(:show_modal, true)
     |> assign(:editing, nil)
     |> assign(:form, to_form(changeset, as: :role_policy))}
  end

  def handle_event("edit_policy", %{"id" => id}, socket) do
    policy = RolePolicies.get_role_policy!(id)
    changeset = RolePolicies.change_role_policy(policy, %{})

    {:noreply,
     socket
     |> assign(:show_modal, true)
     |> assign(:editing, policy)
     |> assign(:form, to_form(changeset, as: :role_policy))}
  end

  def handle_event("close_modal", _, socket) do
    {:noreply, assign(socket, :show_modal, false)}
  end

  def handle_event("validate_policy", %{"role_policy" => params}, socket) do
    policy = socket.assigns.editing || %RolePolicy{}
    changeset = RolePolicies.change_role_policy(policy, params) |> Map.put(:action, :validate)
    {:noreply, assign(socket, :form, to_form(changeset, as: :role_policy))}
  end

  def handle_event("save_policy", %{"role_policy" => params}, socket) do
    result =
      if policy = socket.assigns.editing do
        RolePolicies.update_role_policy(policy, params)
      else
        RolePolicies.create_role_policy(params)
      end

    case result do
      {:ok, _policy} ->
        {:noreply,
         socket
         |> put_flash(:info, "Role policy saved.")
         |> assign(:show_modal, false)
         |> assign(:editing, nil)
         |> load_policies()}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :role_policy))}
    end
  end

  def handle_event("delete_policy", %{"id" => id}, socket) do
    policy = RolePolicies.get_role_policy!(id)
    {:ok, _} = RolePolicies.delete_role_policy(policy)

    {:noreply,
     socket
     |> put_flash(:info, "Role policy deleted.")
     |> load_policies()}
  end

  # ── Options helpers ──────────────────────────────────────────────────────────

  defp role_options do
    RolePolicy.user_types()
    |> Enum.map(&{String.capitalize(Atom.to_string(&1)), &1})
  end

  defp resource_options do
    RolePolicy.resource_types()
    |> Enum.map(fn
      :global -> {"Global (all resources)", :global}
      :community -> {"Community", :community}
      :collection -> {"Collection", :collection}
      :item -> {"Item", :item}
    end)
  end

  defp action_options do
    RolePolicy.policy_actions()
    |> Enum.map(fn
      :manage -> {"Manage (all actions)", :manage}
      :read -> {"Read", :read}
      :submit -> {"Submit", :submit}
      :review -> {"Review", :review}
      :publish -> {"Publish", :publish}
    end)
  end
end
