defmodule KirokuWeb.Admin.CommunityLive.Index do
  use KirokuWeb, :live_view

  alias Kiroku.Repository
  alias Kiroku.Repository.Community

  def render(%{live_action: action} = assigns) when action in [:new, :edit] do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_user} page_title="Communities">
      <div class="max-w-2xl mx-auto space-y-6">
        <div>
          <.link
            patch={~p"/admin/communities"}
            style="color: var(--color-lavender);"
            class="text-sm hover:text-white transition-colors"
          >
            ← Communities
          </.link>
          <h1 class="font-heading text-2xl mt-2" style="color: var(--color-lilac);">
            {if @live_action == :new, do: "New Community", else: "Edit Community"}
          </h1>
        </div>
        <div class="kiroku-card p-6">
          <.form
            for={@form}
            id="community-form"
            phx-submit="save"
            phx-change="validate"
            class="space-y-4"
          >
            <.input field={@form[:name]} type="text" label="Name" required />
            <.input field={@form[:handle]} type="text" label="Handle" required />
            <.input
              field={@form[:parent_community_id]}
              type="select"
              label="Parent community"
              options={@parent_options}
              prompt="— Root community (no parent) —"
            />
            <.input field={@form[:short_description]} type="text" label="Short Description" />
            <.input field={@form[:description]} type="textarea" label="Description" />
            <div class="flex gap-3 pt-2">
              <button
                type="submit"
                class="px-5 py-2.5 rounded-lg font-semibold text-sm"
                style="background: var(--color-patchouli); color: white;"
              >
                Save
              </button>
              <.link
                patch={~p"/admin/communities"}
                class="px-5 py-2.5 rounded-lg font-medium text-sm"
                style="background: rgba(155,126,200,0.1); color: var(--color-wisteria);"
              >
                Cancel
              </.link>
            </div>
          </.form>
        </div>
      </div>
    </Layouts.admin>
    """
  end

  def render(%{live_action: :index} = assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_user} page_title="Communities">
      <div class="space-y-6">
        <div class="flex items-center justify-between">
          <div>
            <h1 class="font-heading text-3xl" style="color: var(--color-lilac);">Communities</h1>
            <p class="text-sm mt-1" style="color: var(--color-quill);">
              Organize communities into a hierarchy. Top-level communities appear on the public browse page.
            </p>
          </div>
          <.link
            patch={~p"/admin/communities/new"}
            class="px-4 py-2 rounded-lg font-medium text-sm flex items-center gap-2"
            style="background: var(--color-patchouli); color: white;"
          >
            <.icon name="hero-plus" class="w-4 h-4" /> New Community
          </.link>
        </div>
        <div class="kiroku-card overflow-hidden">
          <table class="w-full text-sm">
            <thead style="background: rgba(45,27,105,0.5);">
              <tr>
                <th class="px-4 py-3 text-left font-medium" style="color: var(--color-wisteria);">
                  Name
                </th>
                <th class="px-4 py-3 text-left font-medium" style="color: var(--color-wisteria);">
                  Handle
                </th>
                <th class="px-4 py-3 text-left font-medium" style="color: var(--color-wisteria);">
                  Active
                </th>
                <th class="px-4 py-3"></th>
              </tr>
            </thead>
            <tbody id="communities" phx-update="stream">
              <tr
                :for={{id, community} <- @streams.communities}
                id={id}
                style="border-top: 1px solid rgba(155,126,200,0.1);"
              >
                <td class="px-4 py-3" style={"padding-left: #{(community.depth || 0) * 1.5 + 1}rem;"}>
                  <%= if (community.depth || 0) > 0 do %>
                    <span style="color: var(--color-quill);" class="mr-1">└</span>
                  <% end %>
                  <span style="color: var(--color-lilac);">{community.name}</span>
                </td>
                <td class="px-4 py-3 kiroku-handle">{community.handle}</td>
                <td class="px-4 py-3">
                  <%= if community.is_active do %>
                    <span class="status-badge published">Active</span>
                  <% else %>
                    <span class="status-badge withdrawn">Inactive</span>
                  <% end %>
                </td>
                <td class="px-4 py-3 text-right flex items-center gap-3 justify-end">
                  <.link
                    navigate={~p"/admin/communities/#{community.id}"}
                    style="color: var(--color-lavender);"
                    class="hover:text-white transition-colors text-xs"
                  >
                    View
                  </.link>
                  <.link
                    patch={~p"/admin/communities/#{community.id}/edit"}
                    style="color: var(--color-lavender);"
                    class="hover:text-white transition-colors text-xs"
                  >
                    Edit
                  </.link>
                  <button
                    phx-click="delete"
                    phx-value-id={community.id}
                    data-confirm="Delete this community? Its subcommunities will become top-level."
                    class="text-xs transition-colors hover:text-white"
                    style="color: var(--color-ribbon-red);"
                  >
                    Delete
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </Layouts.admin>
    """
  end

  def mount(_params, _session, socket) do
    communities = Repository.list_communities_tree()
    {:ok, stream(socket, :communities, communities)}
  end

  def handle_params(params, _uri, socket) do
    if superadmin?(socket) do
      {:noreply, apply_action(socket, socket.assigns.live_action, params)}
    else
      {:noreply,
       socket
       |> put_flash(:error, "Only superadmins can manage communities.")
       |> push_navigate(to: ~p"/admin")}
    end
  end

  defp apply_action(socket, :index, _params) do
    communities = Repository.list_communities_tree()

    socket
    |> assign(:form, nil)
    |> assign(:current_community, nil)
    |> assign(:parent_options, [])
    |> stream(:communities, communities, reset: true)
  end

  defp apply_action(socket, :new, _params) do
    changeset = Community.changeset(%Community{}, %{})

    socket
    |> assign(:current_community, nil)
    |> assign(:parent_options, parent_select_options(Repository.list_possible_parents_tree(nil)))
    |> assign(:form, to_form(changeset, as: :community))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    community = Repository.get_community!(id)
    changeset = Community.changeset(community, %{})

    socket
    |> assign(:current_community, community)
    |> assign(
      :parent_options,
      parent_select_options(Repository.list_possible_parents_tree(community))
    )
    |> assign(:form, to_form(changeset, as: :community))
  end

  defp parent_select_options(communities) do
    Enum.map(communities, fn community ->
      indent = String.duplicate("\u00A0\u00A0\u00A0", community.depth || 0)
      {"#{indent}#{community.name}", community.id}
    end)
  end

  defp superadmin?(socket) do
    socket.assigns[:current_user] && socket.assigns.current_user.user_type == :superadmin
  end

  def handle_event("validate", %{"community" => params}, socket) do
    community = socket.assigns.current_community || %Community{}
    changeset = community |> Community.changeset(params) |> Map.put(:action, :validate)
    {:noreply, assign(socket, :form, to_form(changeset, as: :community))}
  end

  def handle_event("save", %{"community" => params}, socket) do
    parent_id = normalize_parent_id(params["parent_community_id"])

    params =
      case parent_id do
        :root -> Map.delete(params, "parent_community_id")
        id -> Map.put(params, "parent_community_id", id)
      end

    case socket.assigns.live_action do
      :new ->
        case Repository.create_community(params) do
          {:ok, _community} ->
            {:noreply,
             socket
             |> put_flash(:info, "Community created.")
             |> push_patch(to: ~p"/admin/communities")}

          {:error, changeset} ->
            {:noreply, assign(socket, :form, to_form(changeset, as: :community))}
        end

      :edit ->
        community = socket.assigns.current_community

        case Repository.update_community(community, params) do
          {:ok, _updated} ->
            {:noreply,
             socket
             |> put_flash(:info, "Community updated.")
             |> push_patch(to: ~p"/admin/communities")}

          {:error, changeset} ->
            {:noreply, assign(socket, :form, to_form(changeset, as: :community))}
        end
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    community = Repository.get_community!(id)
    {:ok, _} = Repository.delete_community(community)

    # Re-stream the tree since deleting a node reshuffles the hierarchy.
    communities = Repository.list_communities_tree()

    {:noreply,
     socket
     |> put_flash(:info, "Community deleted.")
     |> stream(:communities, communities, reset: true)}
  end

  # Treat an empty/select-prompt parent id as "no parent".
  defp normalize_parent_id(""), do: :root
  defp normalize_parent_id(nil), do: :root
  defp normalize_parent_id(id), do: id
end
