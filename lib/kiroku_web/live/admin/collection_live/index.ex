defmodule KirokuWeb.Admin.CollectionLive.Index do
  use KirokuWeb, :live_view

  alias Kiroku.Repository
  alias Kiroku.Repository.Collection

  def render(%{live_action: action} = assigns) when action in [:new, :edit] do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_user}>
      <div class="max-w-2xl mx-auto space-y-6">
        <div>
          <.link
            patch={~p"/admin/collections"}
            style="color: var(--color-lavender);"
            class="text-sm hover:text-white transition-colors"
          >
            ← Collections
          </.link>
          <h1 class="font-heading text-2xl mt-2" style="color: var(--color-lilac);">
            {if @live_action == :new, do: "New Collection", else: "Edit Collection"}
          </h1>
        </div>
        <div class="kiroku-card p-6">
          <.form
            for={@form}
            id="collection-form"
            phx-submit="save"
            phx-change="validate"
            class="space-y-4"
          >
            <.input field={@form[:name]} type="text" label="Name" required />
            <.input field={@form[:handle]} type="text" label="Handle" required />
            <div>
              <label class="block text-sm font-medium mb-1.5" style="color: var(--color-wisteria);">
                Community
              </label>
              <select name="collection[community_id]" class="kiroku-search-input" required>
                <option value="">Select community…</option>
                <%= for community <- @communities do %>
                  <option
                    value={community.id}
                    selected={to_string(@form[:community_id].value) == to_string(community.id)}
                  >
                    {community.name}
                  </option>
                <% end %>
              </select>
            </div>
            <.input field={@form[:short_description]} type="text" label="Short Description" />
            <div class="flex gap-3 pt-2">
              <button
                type="submit"
                class="px-5 py-2.5 rounded-lg font-semibold text-sm"
                style="background: var(--color-patchouli); color: white;"
              >
                Save
              </button>
              <.link
                patch={~p"/admin/collections"}
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

  def render(%{live_action: :index} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_user}>
      <div class="space-y-6">
        <div class="flex items-center justify-between">
          <h1 class="font-heading text-3xl" style="color: var(--color-lilac);">Collections</h1>
          <.link
            patch={~p"/admin/collections/new"}
            class="px-4 py-2 rounded-lg font-medium text-sm flex items-center gap-2"
            style="background: var(--color-patchouli); color: white;"
          >
            <.icon name="hero-plus" class="w-4 h-4" /> New Collection
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
                  Community
                </th>
                <th class="px-4 py-3"></th>
              </tr>
            </thead>
            <tbody id="collections" phx-update="stream">
              <tr
                :for={{id, collection} <- @streams.collections}
                id={id}
                style="border-top: 1px solid rgba(155,126,200,0.1);"
              >
                <td class="px-4 py-3" style="color: var(--color-lilac);">{collection.name}</td>
                <td class="px-4 py-3 kiroku-handle">{collection.handle}</td>
                <td class="px-4 py-3" style="color: var(--color-quill);">
                  <%= if Ecto.assoc_loaded?(collection.community) do %>
                    {collection.community.name}
                  <% end %>
                </td>
                <td class="px-4 py-3 text-right flex items-center gap-3 justify-end">
                  <.link
                    navigate={~p"/admin/collections/#{collection.id}"}
                    style="color: var(--color-lavender);"
                    class="text-xs hover:text-white transition-colors"
                  >
                    View
                  </.link>
                  <.link
                    patch={~p"/admin/collections/#{collection.id}/edit"}
                    style="color: var(--color-lavender);"
                    class="text-xs hover:text-white transition-colors"
                  >
                    Edit
                  </.link>
                  <button
                    phx-click="delete"
                    phx-value-id={collection.id}
                    data-confirm="Delete this collection?"
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
    </Layouts.app>
    """
  end

  def mount(_params, _session, socket) do
    collections = Repository.list_collections()
    communities = Repository.list_communities()

    {:ok,
     socket
     |> assign(:communities, communities)
     |> stream(:collections, collections)}
  end

  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket |> assign(:form, nil) |> assign(:current_collection, nil)
  end

  defp apply_action(socket, :new, _params) do
    changeset = Collection.changeset(%Collection{}, %{})

    socket
    |> assign(:current_collection, nil)
    |> assign(:form, to_form(changeset, as: :collection))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    collection = Repository.get_collection!(id)
    changeset = Collection.changeset(collection, %{})

    socket
    |> assign(:current_collection, collection)
    |> assign(:form, to_form(changeset, as: :collection))
  end

  def handle_event("validate", %{"collection" => params}, socket) do
    collection = socket.assigns.current_collection || %Collection{}
    changeset = collection |> Collection.changeset(params) |> Map.put(:action, :validate)
    {:noreply, assign(socket, :form, to_form(changeset, as: :collection))}
  end

  def handle_event("save", %{"collection" => params}, socket) do
    case socket.assigns.live_action do
      :new ->
        case Repository.create_collection(params) do
          {:ok, collection} ->
            {:noreply,
             socket
             |> put_flash(:info, "Collection created.")
             |> stream_insert(:collections, collection, at: 0)
             |> push_patch(to: ~p"/admin/collections")}

          {:error, changeset} ->
            {:noreply, assign(socket, :form, to_form(changeset, as: :collection))}
        end

      :edit ->
        collection = socket.assigns.current_collection

        case Repository.update_collection(collection, params) do
          {:ok, updated} ->
            {:noreply,
             socket
             |> put_flash(:info, "Collection updated.")
             |> stream_insert(:collections, updated)
             |> push_patch(to: ~p"/admin/collections")}

          {:error, changeset} ->
            {:noreply, assign(socket, :form, to_form(changeset, as: :collection))}
        end
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    collection = Repository.get_collection!(id)
    {:ok, _} = Repository.delete_collection(collection)

    {:noreply,
     socket
     |> put_flash(:info, "Collection deleted.")
     |> stream_delete(:collections, collection)}
  end
end
