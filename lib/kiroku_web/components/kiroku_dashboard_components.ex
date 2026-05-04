defmodule KirokuWeb.KirokuDashboardComponents do
  @moduledoc """
  UI components specific to the admin dashboard.

  Includes stat cards, admin tables, role badges, and action bars.
  """
  use Phoenix.Component
  use Gettext, backend: KirokuWeb.Gettext

  # ── Stat Card ─────────────────────────────────────────────────────────────

  @doc """
  Renders a dashboard stat card showing a key metric.

  ## Examples

      <.stat_card value={@stats.items} label="Total Items" />
      <.stat_card value="1,247" label="Published Works" />
  """
  attr :value, :any, required: true
  attr :label, :string, required: true

  def stat_card(assigns) do
    ~H"""
    <div class="kiroku-card p-6 text-center">
      <p class="font-heading text-5xl" style="color: var(--color-patchouli);">{@value}</p>
      <p
        class="font-ui text-xs uppercase tracking-widest mt-2"
        style="color: var(--color-quill);"
      >
        {@label}
      </p>
    </div>
    """
  end

  # ── Admin Table ───────────────────────────────────────────────────────────

  @doc """
  Renders a styled admin data table with column and action slots.

  Columns are defined via the `:col` slot with a `label` attribute.
  The slot block receives each row via `:let`.

  An optional `:action` slot renders a right-aligned actions column.

  ## Examples

      <.admin_table id="users-table" rows={@users}>
        <:col label="Name" :let={user}>{user.name}</:col>
        <:col label="Email" :let={user}>{user.email}</:col>
        <:action :let={user}>
          <.link navigate={~p"/admin/users/\#{user.id}"}>View</.link>
        </:action>
      </.admin_table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true

  slot :col, required: true do
    attr :label, :string
  end

  slot :action

  def admin_table(assigns) do
    ~H"""
    <div class="overflow-x-auto">
      <table class="w-full text-sm">
        <thead>
          <tr style="background: rgba(45,27,105,0.50); border-bottom: 1px solid rgba(155,126,200,0.20);">
            <%= for col <- @col do %>
              <th
                class="text-left px-4 py-3 font-ui text-xs font-semibold uppercase tracking-wider"
                style="color: var(--color-wisteria);"
              >
                {col[:label]}
              </th>
            <% end %>
            <%= if @action != [] do %>
              <th
                class="text-right px-4 py-3 font-ui text-xs font-semibold uppercase tracking-wider"
                style="color: var(--color-wisteria);"
              >
                Actions
              </th>
            <% end %>
          </tr>
        </thead>
        <tbody>
          <%= for {row, i} <- Enum.with_index(@rows) do %>
            <tr
              id={"#{@id}-row-#{i}"}
              class="transition-colors duration-150"
              style="border-bottom: 1px solid rgba(155,126,200,0.06);"
              onmouseover="this.style.background='rgba(155,126,200,0.04)'"
              onmouseout="this.style.background=''"
            >
              <%= for col <- @col do %>
                <td class="px-4 py-3 font-ui" style="color: var(--color-lilac);">
                  {render_slot(col, row)}
                </td>
              <% end %>
              <%= if @action != [] do %>
                <td class="px-4 py-3 text-right">
                  <div class="flex items-center justify-end gap-2">
                    {render_slot(@action, row)}
                  </div>
                </td>
              <% end %>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
    """
  end

  # ── User Role Badge ────────────────────────────────────────────────────────

  @doc """
  Renders a themed badge for a user role.

  ## Examples

      <.user_role_badge role={@user.role} />
      <.user_role_badge role="superadmin" />
  """
  attr :role, :any, required: true

  def user_role_badge(assigns) do
    assigns = assign(assigns, :label, role_label(assigns.role))
    assigns = assign(assigns, :style, role_style(assigns.role))

    ~H"""
    <span
      class="font-ui text-xs font-semibold uppercase tracking-wider px-2.5 py-0.5 rounded"
      style={@style}
    >
      {@label}
    </span>
    """
  end

  defp role_label(role) do
    case to_string(role) do
      "superadmin" -> "Super Admin"
      "admin" -> "Admin"
      "reviewer" -> "Reviewer"
      "submitter" -> "Submitter"
      other -> String.capitalize(other)
    end
  end

  defp role_style(role) do
    case to_string(role) do
      "superadmin" ->
        "color: var(--color-ribbon-gold); background: rgba(212,160,23,0.15); border: 1px solid rgba(212,160,23,0.30);"

      "admin" ->
        "color: var(--color-lavender); background: rgba(155,126,200,0.15); border: 1px solid rgba(155,126,200,0.30);"

      "reviewer" ->
        "color: var(--color-ribbon-sky); background: rgba(122,171,216,0.15); border: 1px solid rgba(122,171,216,0.30);"

      "submitter" ->
        "color: var(--color-dust); background: rgba(155,126,200,0.08); border: 1px solid rgba(155,126,200,0.15);"

      _ ->
        "color: var(--color-quill); background: rgba(155,126,200,0.06); border: 1px solid rgba(155,126,200,0.10);"
    end
  end

  # ── Admin Action Bar ──────────────────────────────────────────────────────

  @doc """
  Renders a horizontal bar of admin action buttons.

  Wrap action buttons inside this component for consistent spacing and alignment.

  ## Examples

      <.admin_action_bar>
        <.link navigate={~p"/admin/communities/new"} class="...">New</.link>
        <button phx-click="export" class="...">Export</button>
      </.admin_action_bar>
  """
  slot :inner_block, required: true

  def admin_action_bar(assigns) do
    ~H"""
    <div class="flex items-center gap-2 flex-wrap">
      {render_slot(@inner_block)}
    </div>
    """
  end
end
