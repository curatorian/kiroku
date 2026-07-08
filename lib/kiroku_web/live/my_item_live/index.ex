defmodule KirokuWeb.MyItemLive.Index do
  use KirokuWeb, :live_view

  import KirokuWeb.KirokuComponents

  alias Kiroku.Repository
  alias Kiroku.Repository.Item
  alias Kiroku.Access.Authorization
  alias Kiroku.Pagination

  @item_types ~w(skripsi memorandum_hukum studi_kasus laporan_proyek karya_kreatif karya_teknologi jurnal_nasional jurnal_internasional prosiding capstone)

  def render(%{live_action: :index} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_user}>
      <div class="space-y-6">
        <div class="flex items-center justify-between">
          <div>
            <h1 class="font-heading text-3xl" style="color: var(--color-lilac);">My Items</h1>
            <p class="text-sm mt-1" style="color: var(--color-quill);">
              Items you have submitted to the repository.
            </p>
          </div>
          <.link
            :if={@can_submit}
            patch={~p"/my/items/new"}
            class="px-4 py-2 rounded-lg font-medium text-sm flex items-center gap-2 transition-colors"
            style="background: var(--color-patchouli); color: white;"
          >
            <.icon name="hero-plus" class="w-4 h-4" /> New Item
          </.link>
        </div>

        <div id="items" phx-update="stream">
          <div class="hidden only:block kiroku-card p-12 text-center">
            <span class="kiroku-kanji text-5xl opacity-30">記</span>
            <p class="mt-4" style="color: var(--color-quill);">
              <%= if @can_submit do %>
                You have not submitted any items yet.
              <% else %>
                You have not submitted any items yet. Submission is currently disabled.
              <% end %>
            </p>
            <.link
              :if={@can_submit}
              patch={~p"/my/items/new"}
              class="mt-4 inline-block px-5 py-2 rounded-lg font-medium text-sm"
              style="background: var(--color-patchouli); color: white;"
            >
              Submit Your First Item
            </.link>
          </div>
          <div
            :for={{id, item} <- @streams.items}
            id={id}
            class="kiroku-card p-5 flex items-start gap-4 mb-3"
          >
            <div class="flex-1 min-w-0 space-y-2">
              <div class="flex items-center gap-2 mb-1.5 flex-wrap">
                <span class="badge-item-type">{item.item_type}</span>
                <span class={["status-badge", to_string(item.status)]}>{item.status}</span>
                <%= if item.publication_year do %>
                  <span
                    class="text-xs px-2 py-0.5 rounded-full"
                    style="background: rgba(155,126,200,0.08); color: var(--color-wisteria);"
                  >
                    {item.publication_year}
                  </span>
                <% end %>
              </div>
              <p class="font-body text-base font-medium" style="color: var(--color-lilac);">
                {item.title}
              </p>
              <p class="kiroku-handle text-xs">{item.handle || item.id}</p>

              <%!-- Abstract (truncated) --%>
              <%= if item.abstract do %>
                <% abstract_text = item.abstract

                truncated_abstract =
                  if String.length(abstract_text) > 120 do
                    String.slice(abstract_text, 0, 117) <> "..."
                  else
                    abstract_text
                  end %>
                <p
                  class="text-sm leading-relaxed line-clamp-2"
                  style="color: var(--color-quill);"
                >
                  {truncated_abstract}
                </p>
              <% end %>

              <%!-- Author information --%>
              <%= if item.student_name do %>
                <div class="flex items-center gap-2">
                  <div
                    class="w-6 h-6 rounded-full flex items-center justify-center shrink-0 text-[10px] font-bold"
                    style="background: rgba(123,79,166,0.2); color: var(--color-patchouli);"
                  >
                    {String.first(item.student_name)}
                  </div>
                  <div class="flex-1 min-w-0">
                    <p class="font-medium text-xs truncate" style="color: var(--color-wisteria);">
                      {item.student_name}
                    </p>
                    <%= if item.student_id do %>
                      <p class="font-mono text-[10px] truncate" style="color: var(--color-quill);">
                        NPM: {item.student_id}
                      </p>
                    <% end %>
                  </div>
                </div>
              <% end %>

              <%!-- Academic information --%>
              <div class="flex flex-wrap gap-1.5 text-[10px]" style="color: var(--color-quill);">
                <%= if item.program_study do %>
                  <span class="px-1.5 py-0.5 rounded" style="background: rgba(155,126,200,0.06);">
                    {item.program_study}
                  </span>
                <% end %>
                <%= if item.faculty do %>
                  <span class="px-1.5 py-0.5 rounded" style="background: rgba(155,126,200,0.06);">
                    {item.faculty}
                  </span>
                <% end %>
              </div>

              <%!-- Date information --%>
              <%= if not is_nil(item.date_submitted) or not is_nil(item.published_at) or not is_nil(item.inserted_at) do %>
                <% display_date =
                  cond do
                    not is_nil(item.date_submitted) -> item.date_submitted
                    not is_nil(item.published_at) -> item.published_at
                    not is_nil(item.inserted_at) -> item.inserted_at
                    true -> nil
                  end

                date_label =
                  cond do
                    not is_nil(item.date_submitted) -> "Submitted"
                    not is_nil(item.published_at) -> "Published"
                    not is_nil(item.inserted_at) -> "Created"
                    true -> ""
                  end %>
                <%= if display_date do %>
                  <div class="flex items-center gap-1.5">
                    <.icon
                      name="hero-calendar"
                      class="w-3 h-3 shrink-0"
                      style="color: var(--color-dust);"
                    />
                    <span class="font-mono text-[10px]" style="color: var(--color-dust);">
                      {date_label}: {Calendar.strftime(display_date, "%d %b %Y")}
                    </span>
                  </div>
                <% end %>
              <% end %>
            </div>
            <div class="flex items-center gap-2 shrink-0">
              <%= if item.status in [:draft, :submitted] do %>
                <.link
                  patch={~p"/my/items/#{item.id}/edit"}
                  class="px-3 py-1.5 rounded-lg text-xs font-medium transition-colors"
                  style="background: rgba(155,126,200,0.12); color: var(--color-wisteria); border: 1px solid rgba(155,126,200,0.2);"
                >
                  Edit
                </.link>
              <% end %>
              <%= if item.status == :draft do %>
                <button
                  phx-click="submit_item"
                  phx-value-id={item.id}
                  class="px-3 py-1.5 rounded-lg text-xs font-medium transition-colors"
                  style="background: rgba(90,158,114,0.15); color: #5A9E72; border: 1px solid rgba(90,158,114,0.3);"
                >
                  Submit
                </button>
              <% end %>
              <%= if item.status == :published do %>
                <.link
                  href={~p"/items/#{item.handle}"}
                  class="px-3 py-1.5 rounded-lg text-xs font-medium"
                  style="background: rgba(90,158,114,0.1); color: #5A9E72; border: 1px solid rgba(90,158,114,0.25);"
                >
                  View
                </.link>
              <% end %>
            </div>
          </div>
        </div>

        <.pagination pagination={@pagination} path="/my/items" params={%{}} />
      </div>
    </Layouts.app>
    """
  end

  def render(%{live_action: action} = assigns) when action in [:new, :edit] do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_user}>
      <div class="max-w-3xl mx-auto space-y-6">
        <div>
          <.link
            patch={~p"/my/items"}
            class="text-sm transition-colors hover:text-white"
            style="color: var(--color-lavender);"
          >
            ← Back to My Items
          </.link>
          <h1 class="font-heading text-3xl mt-2" style="color: var(--color-lilac);">
            {if @live_action == :new, do: "Submit New Item", else: "Edit Item"}
          </h1>
        </div>

        <div class="kiroku-card p-6">
          <.form for={@form} id="item-form" phx-submit="save" phx-change="validate" class="space-y-5">
            <.input field={@form[:title]} type="text" label="Title" required />

            <div>
              <label class="block text-sm font-medium mb-1.5" style="color: var(--color-wisteria);">
                Item Type
              </label>
              <select name="item[item_type]" class="kiroku-search-input">
                <option value="">Select type…</option>
                <%= for type <- @item_types do %>
                  <option value={type} selected={to_string(@form[:item_type].value) == type}>
                    {type |> String.replace("_", " ") |> String.capitalize()}
                  </option>
                <% end %>
              </select>
            </div>

            <div>
              <label class="block text-sm font-medium mb-1.5" style="color: var(--color-wisteria);">
                Collection
              </label>
              <select name="item[collection_id]" class="kiroku-search-input" required>
                <option value="">Select collection…</option>
                <%= for collection <- @collections do %>
                  <option
                    value={collection.id}
                    selected={to_string(@form[:collection_id].value) == to_string(collection.id)}
                  >
                    {collection.name}
                  </option>
                <% end %>
              </select>
            </div>

            <.input field={@form[:abstract]} type="textarea" label="Abstract" />
            <.input field={@form[:abstract_alt]} type="textarea" label="Abstract (Alt Language)" />
            <.input field={@form[:publication_year]} type="number" label="Publication Year" />
            <.input field={@form[:faculty]} type="text" label="Faculty / Department" />

            <div class="flex gap-3 pt-2">
              <button
                type="submit"
                class="px-5 py-2.5 rounded-lg font-semibold text-sm"
                style="background: var(--color-patchouli); color: white;"
              >
                {if @live_action == :new, do: "Create Item", else: "Save Changes"}
              </button>
              <.link
                patch={~p"/my/items"}
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

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    collections = list_all_collections()
    can_submit = Kiroku.Settings.allow_user_submit?() or staff?(user)

    {:ok,
     socket
     |> assign(:collections, collections)
     |> assign(:item_types, @item_types)
     |> assign(:current_item, nil)
     |> assign(:can_submit, can_submit)
     |> assign(:form, nil)
     |> assign(:pagination, Pagination.build(0, 1, 20))
     |> stream(:items, [])}
  end

  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, params) do
    user = socket.assigns.current_user
    page = parse_page(params["page"])

    {items, pagination} =
      Repository.list_items_by_submitter_pagination(user.id, page: page, per_page: 20)

    socket
    |> assign(:page_title, "My Items")
    |> assign(:form, nil)
    |> assign(:current_item, nil)
    |> assign(:pagination, pagination)
    |> stream(:items, items, reset: true)
  end

  defp apply_action(socket, :new, _params) do
    if socket.assigns.can_submit do
      changeset = Item.changeset(%Item{}, %{})

      socket
      |> assign(:page_title, "Submit New Item")
      |> assign(:current_item, nil)
      |> assign(:form, to_form(changeset, as: :item))
    else
      socket
      |> put_flash(:error, "Item submission is currently disabled.")
      |> push_patch(to: ~p"/my/items")
    end
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    user = socket.assigns.current_user
    item = Repository.get_item!(id)

    if Authorization.can?(user, :update, item) do
      changeset = Item.changeset(item, %{})

      socket
      |> assign(:page_title, "Edit Item")
      |> assign(:current_item, item)
      |> assign(:form, to_form(changeset, as: :item))
    else
      socket
      |> put_flash(:error, "Anda tidak memiliki akses untuk mengedit item ini.")
      |> push_patch(to: ~p"/my/items")
    end
  end

  def handle_event("validate", %{"item" => params}, socket) do
    item = socket.assigns.current_item || %Item{}

    changeset =
      item
      |> Item.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: :item))}
  end

  def handle_event("save", %{"item" => params}, socket) do
    user = socket.assigns.current_user

    case socket.assigns.live_action do
      :new ->
        attrs = Map.put(params, "submitter_id", user.id)

        case Repository.create_item(attrs) do
          {:ok, item} ->
            {:noreply,
             socket
             |> put_flash(:info, "Item berhasil dibuat.")
             |> stream_insert(:items, item, at: 0)
             |> push_patch(to: ~p"/my/items")}

          {:error, changeset} ->
            {:noreply, assign(socket, :form, to_form(changeset, as: :item))}
        end

      :edit ->
        item = socket.assigns.current_item

        case Repository.update_item(item, params) do
          {:ok, updated_item} ->
            {:noreply,
             socket
             |> put_flash(:info, "Item berhasil diperbarui.")
             |> stream_insert(:items, updated_item)
             |> push_patch(to: ~p"/my/items")}

          {:error, changeset} ->
            {:noreply, assign(socket, :form, to_form(changeset, as: :item))}
        end
    end
  end

  def handle_event("submit_item", %{"id" => id}, socket) do
    user = socket.assigns.current_user
    item = Repository.get_item!(id)

    if Authorization.can?(user, :update, item) do
      case Repository.update_item(item, %{status: "submitted"}) do
        {:ok, updated_item} ->
          {:noreply,
           socket
           |> put_flash(:info, "Item berhasil dikirim untuk review.")
           |> stream_insert(:items, updated_item)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Gagal mengirim item.")}
      end
    else
      {:noreply, put_flash(socket, :error, "Akses ditolak.")}
    end
  end

  defp list_all_collections do
    Repository.list_active_collections()
  end

  defp staff?(%{user_type: type}) when type in [:admin, :superadmin], do: true
  defp staff?(_), do: false

  defp parse_page(nil), do: 1

  defp parse_page(p) do
    case Integer.parse(p) do
      {n, ""} when n > 0 -> n
      _ -> 1
    end
  end
end
