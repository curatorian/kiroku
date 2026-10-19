defmodule KirokuWeb.Admin.UserLive.Index do
  use KirokuWeb, :live_view

  import KirokuWeb.KirokuComponents

  alias Kiroku.Accounts
  alias Kiroku.Accounts.User
  alias Kiroku.Pagination

  @user_types_all ~w(submitter internal reviewer admin superadmin)
  @user_types_admin ~w(submitter internal reviewer)

  @sort_columns %{
    "email" => :email,
    "user_type" => :user_type,
    "joined" => :inserted_at
  }

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

        <%!-- Search and sort --%>
        <div class="kiroku-card p-4 space-y-4">
          <div class="flex flex-col sm:flex-row gap-3">
            <div class="flex-1">
              <.form for={@search_form} id="search-form" phx-change="search">
                <div class="relative">
                  <span class="absolute left-3 top-1/2 -translate-y-1/2">
                    <.icon
                      name="hero-magnifying-glass"
                      class="w-4 h-4"
                      style="color: var(--color-quill);"
                    />
                  </span>
                  <input
                    type="text"
                    name="q"
                    id="user-search-input"
                    value={@search_query}
                    placeholder="Search by email or name..."
                    class="kiroku-search-input w-full"
                    style="padding-left: 2.5rem;"
                    autocomplete="off"
                  />
                  <button
                    :if={@search_query != ""}
                    type="button"
                    phx-click="clear_search"
                    class="absolute right-3 top-1/2 -translate-y-1/2 text-xs hover:text-white transition-colors"
                    style="color: var(--color-quill);"
                  >
                    Clear
                  </button>
                </div>
              </.form>
            </div>
            <div class="sm:w-48">
              <.form for={@sort_form} id="sort-form" phx-change="sort">
                <select
                  name="sort"
                  id="sort-select"
                  class="kiroku-search-input w-full"
                >
                  <option value="user_type" selected={@sort_by == :user_type}>Role</option>
                  <option value="email" selected={@sort_by == :email}>Email</option>
                  <option value="joined" selected={@sort_by == :inserted_at}>Date Joined</option>
                </select>
              </.form>
            </div>
            <div class="sm:w-32">
              <.form for={@sort_form} id="dir-form" phx-change="sort_dir">
                <select
                  name="dir"
                  id="dir-select"
                  class="kiroku-search-input w-full"
                >
                  <option value="asc" selected={@sort_dir == :asc}>A → Z</option>
                  <option value="desc" selected={@sort_dir == :desc}>Z → A</option>
                </select>
              </.form>
            </div>
          </div>
          <%= if @search_query != "" do %>
            <div class="flex items-center gap-2 text-xs" style="color: var(--color-quill);">
              <span>Active filters:</span>
              <span
                class="px-2 py-1 rounded-full"
                style="background: rgba(155,126,200,0.12); color: var(--color-wisteria);"
              >
                Search: "{@search_query}"
                <button type="button" phx-click="clear_search" class="ml-1 hover:text-white">
                  &times;
                </button>
              </span>
              <button
                type="button"
                phx-click="clear_all_filters"
                class="underline hover:text-white transition-colors"
              >
                Clear all
              </button>
            </div>
          <% end %>
        </div>

        <%!-- Filter tabs --%>
        <div class="flex gap-2 flex-wrap">
          <.link
            patch={user_list_url(assigns, type: "all")}
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
              patch={user_list_url(assigns, type: type)}
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
                  class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider cursor-pointer select-none hover:opacity-80 transition-opacity"
                  style="color: var(--color-wisteria);"
                  phx-click="sort_by"
                  phx-value-sort="user_type"
                >
                  <span class="inline-flex items-center gap-1">
                    Role <.sort_arrow field={:user_type} sort_by={@sort_by} sort_dir={@sort_dir} />
                  </span>
                </th>
                <th
                  class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider"
                  style="color: var(--color-wisteria);"
                >
                  Confirmed
                </th>
                <th
                  class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider cursor-pointer select-none hover:opacity-80 transition-opacity"
                  style="color: var(--color-wisteria);"
                  phx-click="sort_by"
                  phx-value-sort="joined"
                >
                  <span class="inline-flex items-center gap-1">
                    Joined
                    <.sort_arrow field={:inserted_at} sort_by={@sort_by} sort_dir={@sort_dir} />
                  </span>
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

        <.pagination
          pagination={@pagination}
          path="/admin/users"
          params={user_list_params(assigns)}
        />
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

  # ── Sort arrow function component ──────────────────────────────────────────

  defp sort_arrow(assigns) do
    active = assigns.sort_by == assigns.field
    dir = if active, do: assigns.sort_dir, else: :asc

    arrow =
      cond do
        not active -> ""
        dir == :asc -> "\u2191"
        dir == :desc -> "\u2193"
      end

    assigns = assign(assigns, :arrow, arrow)

    ~H"""
    <span :if={@arrow != ""} class="text-[10px] opacity-70">{@arrow}</span>
    """
  end

  # ── Mount & params ───────────────────────────────────────────────────────────

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:total_users, 0)
     |> assign(:filter, "all")
     |> assign(:search_query, "")
     |> assign(:sort_by, :user_type)
     |> assign(:sort_dir, :asc)
     |> assign(:search_form, to_form(%{"q" => ""}))
     |> assign(:sort_form, to_form(%{"sort" => "user_type", "dir" => "asc"}))
     |> assign(:pagination, Pagination.build(0, 1, 20))
     |> assign(:available_types, available_types_for(socket.assigns.current_user))
     |> assign(:form, nil)
     |> stream(:users, [])}
  end

  def handle_params(params, _uri, socket) do
    require Logger
    Logger.info("[UserLive] handle_params params=#{inspect(params)}")
    filter = Map.get(params, "type", "all")
    search = Map.get(params, "q", "") |> String.trim()
    sort_by = Map.get(params, "sort", "user_type") |> parse_sort_by()
    sort_dir = Map.get(params, "dir", "asc") |> parse_sort_dir()
    page = parse_page(params["page"])

    {users, pagination} =
      Accounts.list_users_with_policies_pagination(
        type: filter,
        search: search,
        sort_by: sort_by,
        sort_dir: sort_dir,
        page: page,
        per_page: 20
      )

    socket =
      socket
      |> assign(:total_users, pagination.total_count)
      |> assign(:filter, filter)
      |> assign(:search_query, search)
      |> assign(:sort_by, sort_by)
      |> assign(:sort_dir, sort_dir)
      |> assign(:search_form, to_form(%{"q" => search}))
      |> assign(
        :sort_form,
        to_form(%{"sort" => to_string(sort_by), "dir" => to_string(sort_dir)})
      )
      |> assign(:pagination, pagination)
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

  def handle_event("search", %{"q" => query}, socket) do
    {:noreply, push_patch(socket, to: build_params(socket.assigns, q: query))}
  end

  def handle_event("sort", %{"sort" => sort}, socket) do
    {:noreply, push_patch(socket, to: build_params(socket.assigns, sort: sort, dir: "asc"))}
  end

  def handle_event("sort_dir", %{"dir" => dir}, socket) do
    {:noreply, push_patch(socket, to: build_params(socket.assigns, dir: dir))}
  end

  def handle_event("sort_by", %{"sort" => sort}, socket) do
    require Logger

    Logger.info(
      "[UserLive] sort_by sort=#{sort} current_sort=#{socket.assigns.sort_by} current_dir=#{socket.assigns.sort_dir}"
    )

    # Toggle direction if clicking the same column
    new_dir =
      if sort == to_string(socket.assigns.sort_by) and socket.assigns.sort_dir == :asc,
        do: "desc",
        else: "asc"

    Logger.info(
      "[UserLive] sort_by new_dir=#{new_dir} url=#{build_params(socket.assigns, sort: sort, dir: new_dir)}"
    )

    {:noreply, push_patch(socket, to: build_params(socket.assigns, sort: sort, dir: new_dir))}
  end

  def handle_event("clear_search", _, socket) do
    {:noreply, push_patch(socket, to: build_params(socket.assigns, q: ""))}
  end

  def handle_event("clear_all_filters", _, socket) do
    {:noreply, push_patch(socket, to: ~p"/admin/users")}
  end

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

  # ── URL building ────────────────────────────────────────────────────────────

  defp user_list_params(assigns) do
    %{
      "q" => assigns.search_query,
      "type" => if(assigns.filter != "all", do: assigns.filter),
      "sort" => to_string(assigns.sort_by),
      "dir" => to_string(assigns.sort_dir)
    }
    |> Enum.reject(fn
      {_, nil} -> true
      {_, ""} -> true
      _ -> false
    end)
    |> Map.new()
  end

  defp user_list_url(assigns, overrides) do
    params =
      assigns
      |> user_list_params()
      |> Map.merge(Map.new(overrides, fn {k, v} -> {to_string(k), v} end))
      |> Enum.reject(fn
        {_, nil} -> true
        {_, ""} -> true
        _ -> false
      end)
      |> Map.new()

    "/admin/users?#{URI.encode_query(params)}"
  end

  defp build_params(state, overrides) do
    base = %{
      "q" => Map.get(state, :search_query, ""),
      "type" => if(Map.get(state, :filter, "all") != "all", do: Map.get(state, :filter)),
      "sort" => to_string(Map.get(state, :sort_by, :user_type)),
      "dir" => to_string(Map.get(state, :sort_dir, :asc))
    }

    params =
      base
      |> Map.merge(Map.new(overrides, fn {k, v} -> {to_string(k), v} end))
      |> Enum.reject(fn
        {_, nil} -> true
        {_, ""} -> true
        _ -> false
      end)
      |> Map.new()

    query = URI.encode_query(params)
    "/admin/users?#{query}"
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

  defp role_badge_class(:superadmin), do: "submitted"
  defp role_badge_class(:admin), do: "under-review"
  defp role_badge_class(:reviewer), do: "embargoed"
  defp role_badge_class(:internal), do: "published"
  defp role_badge_class(:submitter), do: "draft"
  defp role_badge_class(_), do: "draft"

  defp parse_sort_by(value) do
    Map.get(@sort_columns, value, :user_type)
  end

  defp parse_sort_dir("desc"), do: :desc
  defp parse_sort_dir(_), do: :asc

  defp parse_page(nil), do: 1

  defp parse_page(p) do
    case Integer.parse(p) do
      {n, ""} when n > 0 -> n
      _ -> 1
    end
  end
end
