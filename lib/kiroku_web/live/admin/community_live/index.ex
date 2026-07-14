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
            <.input
              field={@form[:access_level]}
              type="select"
              label="Visibility"
              options={[
                {"Open — visible to everyone", "open"},
                {"Internal — logged-in users only", "internal"},
                {"Restricted — staff only", "restricted"},
                {"Closed — hidden (admin only)", "closed"}
              ]}
            />
            <.input
              field={@form[:is_active]}
              type="checkbox"
              label="Active (visible in public browse)"
            />
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
              Click a community to expand or collapse its subcommunities.
            </p>
          </div>
          <div class="flex items-center gap-2">
            <button
              type="button"
              phx-click="expand_all"
              class="px-3 py-2 rounded-lg text-sm font-medium"
              style="background: rgba(155,126,200,0.08); color: var(--color-wisteria);"
            >
              Expand All
            </button>
            <button
              type="button"
              phx-click="collapse_all"
              class="px-3 py-2 rounded-lg text-sm font-medium"
              style="background: rgba(155,126,200,0.08); color: var(--color-wisteria);"
            >
              Collapse All
            </button>
            <.link
              patch={~p"/admin/communities/new"}
              class="px-4 py-2 rounded-lg font-medium text-sm flex items-center gap-2"
              style="background: var(--color-patchouli); color: white;"
            >
              <.icon name="hero-plus" class="w-4 h-4" /> New
            </.link>
          </div>
        </div>

        <div class="kiroku-card overflow-hidden">
          <%= if @tree_rows == [] do %>
            <div class="p-12 text-center">
              <.icon name="hero-building-library" class="w-12 h-12 mx-auto opacity-30" />
              <p class="mt-3 text-sm" style="color: var(--color-quill);">
                No communities yet. Create one to get started.
              </p>
            </div>
          <% else %>
            <div id="community-tree">
              <%= for {community, depth, has_children, is_collapsed} <- @tree_rows do %>
                <div
                  id={"community-row-#{community.id}"}
                  class="flex items-center gap-2 px-4 py-3 transition-colors hover:bg-white/[0.02]"
                  style={"padding-left: #{depth * 1.5 + 1}rem; border-top: 1px solid rgba(155,126,200,0.08);"}
                >
                  <button
                    type="button"
                    phx-click="toggle_collapse"
                    phx-value-id={community.id}
                    class="shrink-0 p-1 rounded transition-colors hover:bg-white/5"
                    style="color: var(--color-quill);"
                  >
                    <%= if has_children do %>
                      <.icon
                        name={if is_collapsed, do: "hero-chevron-right", else: "hero-chevron-down"}
                        class="w-4 h-4"
                      />
                    <% else %>
                      <span class="inline-block w-4 h-4"></span>
                    <% end %>
                  </button>

                  <.icon
                    name={if depth == 0, do: "hero-building-library", else: "hero-folder"}
                    class="w-4 h-4 shrink-0"
                    style="color: var(--color-patchouli);"
                  />

                  <div class="flex-1 min-w-0">
                    <span
                      class="text-sm font-medium truncate"
                      style={if depth == 0, do: "color: var(--color-lilac);", else: "color: var(--color-wisteria);"}
                    >
                      {community.name}
                    </span>
                    <span class="kiroku-handle ml-2" style="display: inline-block;">
                      {community.handle}
                    </span>
                  </div>

                  <%= if community.is_active do %>
                    <span class="status-badge published text-xs">Active</span>
                  <% else %>
                    <span class="status-badge withdrawn text-xs">Inactive</span>
                  <% end %>

                  <span class={"status-badge #{access_badge_class(community.access_level)} text-xs"}>
                    {community.access_level}
                  </span>

                  <div class="flex items-center gap-2 shrink-0 ml-2">
                    <.link
                      navigate={~p"/admin/communities/#{community.id}"}
                      class="text-xs transition-colors hover:text-white"
                      style="color: var(--color-lavender);"
                    >
                      View
                    </.link>
                    <.link
                      patch={~p"/admin/communities/#{community.id}/edit"}
                      class="text-xs transition-colors hover:text-white"
                      style="color: var(--color-lavender);"
                    >
                      Edit
                    </.link>
                    <button
                      type="button"
                      phx-click="delete"
                      phx-value-id={community.id}
                      data-confirm="Delete this community? Its subcommunities will become top-level."
                      class="text-xs transition-colors hover:text-white"
                      style="color: var(--color-ribbon-red);"
                    >
                      Delete
                    </button>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
    </Layouts.admin>
    """
  end

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:collapsed, MapSet.new())
     |> assign(:parent_ids, MapSet.new())
     |> assign(:communities, [])
     |> assign(:tree_rows, [])}
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
    communities = Repository.list_communities_tree(scope: :staff)
    parent_ids = communities_with_children(communities)

    socket
    |> assign(:communities, communities)
    |> assign(:parent_ids, parent_ids)
    |> assign(:form, nil)
    |> assign(:current_community, nil)
    |> assign(:parent_options, [])
    |> assign(:tree_rows, build_tree_rows(communities, socket.assigns.collapsed, parent_ids))
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

    communities = Repository.list_communities_tree(scope: :staff)
    parent_ids = communities_with_children(communities)

    {:noreply,
     socket
     |> put_flash(:info, "Community deleted.")
     |> assign(:communities, communities)
     |> assign(:parent_ids, parent_ids)
     |> assign(:tree_rows, build_tree_rows(communities, socket.assigns.collapsed, parent_ids))}
  end

  def handle_event("toggle_collapse", %{"id" => id}, socket) do
    collapsed =
      if MapSet.member?(socket.assigns.collapsed, id) do
        MapSet.delete(socket.assigns.collapsed, id)
      else
        MapSet.put(socket.assigns.collapsed, id)
      end

    {:noreply,
     socket
     |> assign(:collapsed, collapsed)
     |> assign(:tree_rows, build_tree_rows(socket.assigns.communities, collapsed, socket.assigns.parent_ids))}
  end

  def handle_event("expand_all", _params, socket) do
    collapsed = MapSet.new()

    {:noreply,
     socket
     |> assign(:collapsed, collapsed)
     |> assign(:tree_rows, build_tree_rows(socket.assigns.communities, collapsed, socket.assigns.parent_ids))}
  end

  def handle_event("collapse_all", _params, socket) do
    collapsed =
      socket.assigns.communities
      |> Enum.filter(&(MapSet.member?(socket.assigns.parent_ids, &1.id)))
      |> Enum.map(& &1.id)
      |> MapSet.new()

    {:noreply,
     socket
     |> assign(:collapsed, collapsed)
     |> assign(:tree_rows, build_tree_rows(socket.assigns.communities, collapsed, socket.assigns.parent_ids))}
  end

  # Treat an empty/select-prompt parent id as "no parent".
  defp normalize_parent_id(""), do: :root
  defp normalize_parent_id(nil), do: :root
  defp normalize_parent_id(id), do: id

  defp access_badge_class(:open), do: "published"
  defp access_badge_class(:internal), do: "submitted"
  defp access_badge_class(:restricted), do: "embargoed"
  defp access_badge_class(:closed), do: "withdrawn"
  defp access_badge_class(_), do: "draft"

  # ── Tree helpers ────────────────────────────────────────────────────────────

  # Returns a MapSet of community IDs that have at least one subcommunity.
  defp communities_with_children(communities) do
    communities
    |> Enum.filter(& &1.parent_community_id)
    |> Enum.map(& &1.parent_community_id)
    |> MapSet.new()
  end

  # Builds the visible list of {community, depth, has_children, is_collapsed}
  # tuples, skipping descendants of any collapsed community.
  defp build_tree_rows(communities, collapsed, parent_ids) do
    by_parent =
      Enum.group_by(communities, fn c ->
        if c.parent_community_id, do: to_string(c.parent_community_id), else: nil
      end)

    build_rows_recursive(by_parent, nil, 0, collapsed, parent_ids, MapSet.new())
  end

  defp build_rows_recursive(by_parent, parent_id, depth, collapsed, parent_ids, hidden_ancestors) do
    key = if parent_id, do: to_string(parent_id), else: nil
    children = Map.get(by_parent, key, [])
    parent_is_hidden = parent_id != nil and MapSet.member?(hidden_ancestors, parent_id)

    Enum.flat_map(children, fn community ->
      is_collapsed = MapSet.member?(collapsed, community.id)
      has_children = MapSet.member?(parent_ids, community.id)
      row = {community, depth, has_children, is_collapsed}

      if parent_is_hidden do
        []
      else
        new_hidden =
          if is_collapsed,
            do: MapSet.put(hidden_ancestors, community.id),
            else: hidden_ancestors

        child_rows =
          build_rows_recursive(by_parent, community.id, depth + 1, collapsed, parent_ids, new_hidden)

        [row | child_rows]
      end
    end)
  end
end
