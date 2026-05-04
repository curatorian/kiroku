# Review Workflow

## Kiroku — Submission Review & Approval Workflow

---

## 0. Overview

A submission goes through a finite state machine (FSM) from creation to publication.
The workflow has three actor roles:

- **Submitter** — student or depositor who created the item
- **Reviewer** — librarian or designated staff who first inspects the submission
- **Admin** — institution administrator who makes the final publication decision

The FSM is enforced at the **context layer** (`Kiroku.Repository`), not in the LiveView.

---

## 1. Status Finite State Machine

```
                 ┌────────────────────────────────────┐
                 │            SUBMITTER                │
                 │                                     ▼
              [draft] ──submit──> [submitted] ──────> [withdrawn]
                                       │                  ▲
                                       │ assign_reviewer  │ withdraw (any)
                                       ▼                  │
                               [under_review] ─────────────
                                       │
                              ┌────────┴────────┐
                              ▼                  ▼
                        [approved]           [revision_requested]
                              │                  │
                              │                  └──> [submitted] (resubmit)
                              ▼
                        [published]
```

### Valid transitions

| From            | Event                | To              | Actor             |
| --------------- | -------------------- | --------------- | ----------------- |
| `:draft`        | `submit/1`           | `:submitted`    | Submitter         |
| `:submitted`    | `start_review/2`     | `:under_review` | Reviewer / Admin  |
| `:submitted`    | `withdraw/1`         | `:withdrawn`    | Submitter / Admin |
| `:under_review` | `request_revision/2` | `:submitted`    | Reviewer / Admin  |
| `:under_review` | `reject/2`           | `:withdrawn`    | Admin             |
| `:under_review` | `approve/1`          | `:published`    | Admin             |
| `:under_review` | `withdraw/1`         | `:withdrawn`    | Admin             |
| `:published`    | `withdraw/1`         | `:withdrawn`    | Admin             |

---

## 2. Schema Changes

### 2.1 New fields on `items` table

Add a migration to add review-related columns:

```bash
mix ecto.gen.migration add_review_fields_to_items
```

```elixir
# priv/repo/migrations/TIMESTAMP_add_review_fields_to_items.exs
defmodule Kiroku.Repo.Migrations.AddReviewFieldsToItems do
  use Ecto.Migration

  def change do
    alter table(:items) do
      add :review_note,    :text,    null: true    # latest reviewer comment
      add :reviewed_by_id, :bigint,  null: true    # FK to users.id — last reviewer
      add :reviewed_at,    :utc_datetime_usec, null: true
    end

    alter table(:items) do
      modify :reviewed_by_id, references(:users, on_delete: :nilify_all)
    end
  end
end
```

### 2.2 `Item` schema additions

```elixir
# lib/kiroku/repository/item.ex — add to schema "items" do ... end

field :review_note,    :string
field :reviewed_at,    :utc_datetime_usec
belongs_to :reviewed_by, Kiroku.Accounts.User, foreign_key: :reviewed_by_id
```

---

## 3. Context Functions in `Kiroku.Repository`

All workflow transitions live in `lib/kiroku/repository.ex`. Each function:

1. Validates the current status allows the transition
2. Persists the new status (and note/reviewer if provided)
3. Triggers an async Oban job for email notification

```elixir
# lib/kiroku/repository.ex

alias Kiroku.Workers.ReviewNotifier

@doc """
Submitter moves a draft item to submitted for review.
"""
def submit_item(%Item{status: :draft} = item) do
  item
  |> Item.status_changeset(%{status: :submitted, submitted_at: DateTime.utc_now()})
  |> Repo.update()
  |> tap_notify(:submitted)
end

def submit_item(%Item{}), do: {:error, :invalid_transition}

@doc """
A reviewer picks up the submission and begins review.
"""
def start_review(%Item{status: :submitted} = item, reviewer) do
  item
  |> Item.review_changeset(%{
    status:          :under_review,
    reviewed_by_id:  reviewer.id,
    reviewed_at:     DateTime.utc_now()
  })
  |> Repo.update()
  |> tap_notify(:review_started)
end

def start_review(%Item{}, _), do: {:error, :invalid_transition}

@doc """
Admin approves and publishes the item.
"""
def approve_item(%Item{status: :under_review} = item, reviewer) do
  item
  |> Item.review_changeset(%{
    status:          :published,
    discoverable:    true,
    reviewed_by_id:  reviewer.id,
    reviewed_at:     DateTime.utc_now(),
    review_note:     nil
  })
  |> Repo.update()
  |> tap_notify(:approved)
end

def approve_item(%Item{}, _), do: {:error, :invalid_transition}

@doc """
Reviewer/Admin requests the submitter to revise their submission.
The item is returned to :submitted so it can be resubmitted.
"""
def request_revision(%Item{status: :under_review} = item, reviewer, note) do
  item
  |> Item.review_changeset(%{
    status:          :submitted,
    reviewed_by_id:  reviewer.id,
    reviewed_at:     DateTime.utc_now(),
    review_note:     note
  })
  |> Repo.update()
  |> tap_notify(:revision_requested)
end

def request_revision(%Item{}, _, _), do: {:error, :invalid_transition}

@doc """
Admin rejects the item outright. Sets status to :withdrawn.
"""
def reject_item(%Item{status: :under_review} = item, reviewer, note) do
  item
  |> Item.review_changeset(%{
    status:          :withdrawn,
    reviewed_by_id:  reviewer.id,
    reviewed_at:     DateTime.utc_now(),
    review_note:     note
  })
  |> Repo.update()
  |> tap_notify(:rejected)
end

def reject_item(%Item{}, _, _), do: {:error, :invalid_transition}

@doc """
Withdraws an item. Allowed by submitter (own item) or admin (any item).
"""
def withdraw_item(%Item{status: status} = item)
    when status in [:submitted, :under_review, :published] do
  item
  |> Item.status_changeset(%{status: :withdrawn, discoverable: false})
  |> Repo.update()
  |> tap_notify(:withdrawn)
end

def withdraw_item(%Item{}), do: {:error, :invalid_transition}

# ── Private ────────────────────────────────────────────────────────────────

defp tap_notify({:ok, item} = result, event) do
  %{item_id: item.id, event: event}
  |> Kiroku.Workers.ReviewNotifier.new()
  |> Oban.insert()

  result
end

defp tap_notify(error, _event), do: error
```

### 3.1 `Item` Changesets for Review

```elixir
# lib/kiroku/repository/item.ex

def status_changeset(item, attrs) do
  item
  |> cast(attrs, [:status, :discoverable, :submitted_at])
  |> validate_required([:status])
end

def review_changeset(item, attrs) do
  item
  |> cast(attrs, [:status, :discoverable, :review_note, :reviewed_by_id, :reviewed_at])
  |> validate_required([:status])
end
```

---

## 4. Oban `ReviewNotifier` Worker

```elixir
# lib/kiroku/workers/review_notifier.ex
defmodule Kiroku.Workers.ReviewNotifier do
  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias Kiroku.{Repository, Accounts, Notifications}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"item_id" => item_id, "event" => event}}) do
    item = Repository.get_item!(item_id) |> Repo.preload(:submitter)
    event_atom = String.to_existing_atom(event)

    case event_atom do
      :approved           -> Notifications.notify_item_approved(item)
      :rejected           -> Notifications.notify_item_rejected(item)
      :revision_requested -> Notifications.notify_revision_requested(item)
      :submitted          -> Notifications.notify_item_submitted(item)
      _                   -> :ok
    end
  end
end
```

---

## 5. Email Notifications (`Kiroku.Notifications`)

Add to `lib/kiroku/notifications.ex` (or `user_notifier.ex` if that's the established pattern):

```elixir
def notify_item_approved(%Item{} = item) do
  submitter = item.submitter

  new()
  |> to({submitter.name, submitter.email})
  |> from({"Kiroku Repository", "no-reply@#{institution_domain()}"})
  |> subject("Your submission has been approved — #{item.title}")
  |> render_body("item_approved.html", item: item, user: submitter)
  |> deliver()
end

def notify_item_rejected(%Item{} = item) do
  submitter = item.submitter

  new()
  |> to({submitter.name, submitter.email})
  |> from({"Kiroku Repository", "no-reply@#{institution_domain()}"})
  |> subject("Your submission was not accepted — #{item.title}")
  |> render_body("item_rejected.html", item: item, user: submitter, note: item.review_note)
  |> deliver()
end

def notify_revision_requested(%Item{} = item) do
  submitter = item.submitter

  new()
  |> to({submitter.name, submitter.email})
  |> from({"Kiroku Repository", "no-reply@#{institution_domain()}"})
  |> subject("Revisions requested for your submission — #{item.title}")
  |> render_body("item_revision_requested.html", item: item, user: submitter, note: item.review_note)
  |> deliver()
end

def notify_item_submitted(%Item{} = item) do
  # Notify all admin users that a new submission is ready for review
  Kiroku.Accounts.list_users_by_role(:admin)
  |> Enum.each(fn admin ->
    new()
    |> to({admin.name, admin.email})
    |> from({"Kiroku Repository", "no-reply@#{institution_domain()}"})
    |> subject("New submission awaiting review — #{item.title}")
    |> render_body("item_submitted.html", item: item, admin: admin)
    |> deliver()
  end)
end

defp institution_domain do
  Application.get_env(:kiroku, :institution_domain, "kiroku.example.com")
end
```

---

## 6. Admin Review LiveView

### Route

```elixir
# lib/kiroku_web/router.ex — inside live_session :admin block
live "/admin/items/:id/review", Admin.ItemLive.Review, :review
```

### Module

```elixir
# lib/kiroku_web/live/admin/item_live/review.ex
defmodule KirokuWeb.Admin.ItemLive.Review do
  use KirokuWeb, :live_view

  alias Kiroku.{Repository, Content}
  alias Kiroku.Access.Authorization

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    item =
      Repository.get_item!(id)
      |> Kiroku.Repo.preload([:submitter, :bitstreams, :item_keywords])

    socket =
      socket
      |> assign(:item, item)
      |> assign(:review_form, to_form(%{"note" => ""}, as: :review))
      |> assign(:page_title, "Review: #{item.title}")

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="review-page" class="max-w-4xl mx-auto px-4 py-8 space-y-8">
        <%!-- Item metadata --%>
        <div id="review-metadata" class="rounded-xl p-6 space-y-4"
             style="background: var(--color-surface-2);">
          <h1 class="text-2xl font-bold" style="color: var(--color-kiroku);">{@item.title}</h1>
          <div class="grid grid-cols-2 gap-4 text-sm">
            <div>
              <span class="font-medium" style="color: var(--color-text-muted);">Submitter</span>
              <p>{@item.submitter.name} ({@item.submitter.email})</p>
            </div>
            <div>
              <span class="font-medium" style="color: var(--color-text-muted);">Type</span>
              <p>{@item.item_type}</p>
            </div>
            <div>
              <span class="font-medium" style="color: var(--color-text-muted);">Submitted</span>
              <p>{@item.date_submitted}</p>
            </div>
            <div>
              <span class="font-medium" style="color: var(--color-text-muted);">Status</span>
              <p class="capitalize">{@item.status}</p>
            </div>
          </div>
          <%= if @item.abstract do %>
            <div>
              <span class="font-medium" style="color: var(--color-text-muted);">Abstract</span>
              <p class="mt-1 text-sm leading-relaxed">{@item.abstract}</p>
            </div>
          <% end %>
          <%= if @item.item_keywords != [] do %>
            <div>
              <span class="font-medium" style="color: var(--color-text-muted);">Keywords</span>
              <div class="flex flex-wrap gap-1 mt-1">
                <span :for={kw <- @item.item_keywords}
                      class="text-xs px-2 py-0.5 rounded-full"
                      style="background: var(--color-surface-3); color: var(--color-kiroku);">
                  {kw.keyword}
                </span>
              </div>
            </div>
          <% end %>
        </div>

        <%!-- Files --%>
        <div id="review-files" class="space-y-2">
          <h2 class="text-lg font-semibold" style="color: var(--color-text);">Files</h2>
          <div id="bitstream-list" phx-update="stream">
            <div :for={{id, bs} <- @streams.bitstreams} id={id}
                 class="flex items-center gap-3 py-2 px-4 rounded-lg hover:opacity-80"
                 style="background: var(--color-surface-2);">
              <.icon name="hero-document" class="w-5 h-5" style="color: var(--color-wisteria);" />
              <div class="flex-1 min-w-0">
                <p class="text-sm font-medium truncate">{bs.filename}</p>
                <p class="text-xs" style="color: var(--color-text-muted);">
                  {bs.bundle_name} · {bs.description}
                </p>
              </div>
              <a href={~p"/items/#{@item.id}/bitstreams/#{bs.id}"}
                 target="_blank"
                 class="text-xs px-2 py-1 rounded"
                 style="background: var(--color-patchouli); color: white;">
                View
              </a>
            </div>
          </div>
        </div>

        <%!-- Review actions --%>
        <%= if @item.status in [:submitted, :under_review] do %>
          <div id="review-actions" class="rounded-xl p-6 space-y-4"
               style="background: var(--color-surface-2);">
            <h2 class="text-lg font-semibold" style="color: var(--color-text);">Review Decision</h2>
            <.form for={@review_form} id="review-form" phx-submit="submit_review">
              <.input
                field={@review_form[:note]}
                type="textarea"
                label="Note to submitter (optional)"
                placeholder="Describe what needs to be revised, or leave blank for approval..."
                rows="4"
              />
              <div class="flex gap-3 mt-4">
                <%= if @item.status == :submitted do %>
                  <button type="button" id="btn-start-review"
                          phx-click="start_review"
                          class="px-4 py-2 rounded-lg text-sm font-medium transition-all"
                          style="background: var(--color-wisteria); color: white;">
                    Start Review
                  </button>
                <% end %>
                <%= if @item.status == :under_review do %>
                  <button type="submit" id="btn-approve"
                          name="action" value="approve"
                          class="px-4 py-2 rounded-lg text-sm font-medium transition-all"
                          style="background: #22c55e; color: white;">
                    <.icon name="hero-check" class="w-4 h-4 inline mr-1" />
                    Approve & Publish
                  </button>
                  <button type="submit" id="btn-revision"
                          name="action" value="revision"
                          class="px-4 py-2 rounded-lg text-sm font-medium transition-all"
                          style="background: var(--color-patchouli); color: white;">
                    <.icon name="hero-arrow-path" class="w-4 h-4 inline mr-1" />
                    Request Revision
                  </button>
                  <button type="submit" id="btn-reject"
                          name="action" value="reject"
                          class="px-4 py-2 rounded-lg text-sm font-medium transition-all"
                          style="background: var(--color-ribbon-red); color: white;">
                    <.icon name="hero-x-mark" class="w-4 h-4 inline mr-1" />
                    Reject
                  </button>
                <% end %>
              </div>
            </.form>
          </div>
        <% end %>

        <%!-- Review note display (if already reviewed) --%>
        <%= if @item.review_note do %>
          <div id="review-note" class="rounded-xl p-4 border"
               style="border-color: var(--color-wisteria); background: var(--color-surface-2);">
            <p class="text-sm font-medium" style="color: var(--color-text-muted);">
              Review note from {@item.reviewed_by_id && "reviewer"}:
            </p>
            <p class="mt-1 text-sm">{@item.review_note}</p>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("start_review", _params, socket) do
    reviewer = socket.assigns.current_scope.user
    item = socket.assigns.item

    case Repository.start_review(item, reviewer) do
      {:ok, updated_item} ->
        item_with_preloads =
          updated_item |> Kiroku.Repo.preload([:submitter, :bitstreams, :item_keywords])
        {:noreply,
         socket
         |> put_flash(:info, "Review started.")
         |> assign(:item, item_with_preloads)}

      {:error, :invalid_transition} ->
        {:noreply, put_flash(socket, :error, "Cannot start review from current status.")}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, "Error: #{inspect(changeset)}")}
    end
  end

  @impl true
  def handle_event("submit_review", %{"action" => action, "review" => %{"note" => note}}, socket) do
    reviewer = socket.assigns.current_scope.user
    item = socket.assigns.item

    result =
      case action do
        "approve"  -> Repository.approve_item(item, reviewer)
        "revision" -> Repository.request_revision(item, reviewer, note)
        "reject"   -> Repository.reject_item(item, reviewer, note)
        _          -> {:error, :unknown_action}
      end

    case result do
      {:ok, updated_item} ->
        item_with_preloads =
          updated_item |> Kiroku.Repo.preload([:submitter, :bitstreams, :item_keywords])

        flash_msg =
          case action do
            "approve"  -> "Item approved and published."
            "revision" -> "Revision requested. Submitter has been notified."
            "reject"   -> "Item rejected."
            _          -> "Done."
          end

        {:noreply,
         socket
         |> put_flash(:info, flash_msg)
         |> assign(:item, item_with_preloads)}

      {:error, :invalid_transition} ->
        {:noreply, put_flash(socket, :error, "Invalid state transition.")}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, "Error: #{inspect(changeset)}")}
    end
  end

  @impl true
  def mount(params, session, socket) do
    case super(params, session, socket) do
      {:ok, socket} ->
        item = socket.assigns.item
        {:ok, stream(socket, :bitstreams, item.bitstreams)}
      other -> other
    end
  end
end
```

> **Note**: The `stream/3` call for bitstreams must happen in `mount/3` after calling the
> standard mount logic. The template uses `@streams.bitstreams` and `phx-update="stream"`.

---

## 7. Admin Item List — Status Filter

The admin item index page (`Admin.ItemLive.Index`) should filter by status. Add a status
select to the top of the list:

```heex
<%!-- Status filter tabs in admin item list --%>
<div id="status-filter-tabs" class="flex gap-1 text-sm mb-4">
  <.link :for={status <- ~w(all submitted under_review published withdrawn draft)}
         id={"tab-#{status}"}
         navigate={~p"/admin/items?status=#{status}"}
         class={["px-3 py-1 rounded-full transition-all",
                 if(@selected_status == status,
                   do: "font-bold",
                   else: "hover:opacity-80")]}
         style={if @selected_status == status,
                  do: "background: var(--color-patchouli); color: white;",
                  else: "background: var(--color-surface-3); color: var(--color-text);"}>
    {String.replace(status, "_", " ") |> String.capitalize()}
  </.link>
</div>
```

In the LiveView, read the `?status=` query param and filter the `list_items/1` query:

```elixir
@impl true
def handle_params(%{"status" => status} = _params, _uri, socket) do
  status_filter = if status == "all", do: nil, else: String.to_existing_atom(status)
  items = Repository.list_items(status: status_filter)
  {:noreply,
   socket
   |> assign(:selected_status, status)
   |> stream(:items, items, reset: true)}
end

def handle_params(_params, _uri, socket) do
  items = Repository.list_items(status: :submitted)
  {:noreply,
   socket
   |> assign(:selected_status, "submitted")
   |> stream(:items, items, reset: true)}
end
```

---

## 8. Submitter-Facing Review Status

On `MyItemLive.Index`, each item row shows the current status with color coding and, if
revision was requested, shows the `review_note` inline:

```heex
<%!-- Status badge with review note --%>
<div class="text-sm">
  <span class={["px-2 py-0.5 rounded-full text-xs font-medium",
    case item.status do
      :published  -> "bg-green-100 text-green-800"
      :under_review -> "bg-blue-100 text-blue-800"
      :submitted  -> "bg-yellow-100 text-yellow-800"
      :withdrawn  -> "bg-gray-100 text-gray-500"
      _           -> "bg-gray-100 text-gray-600"
    end]}>
    {item.status |> to_string() |> String.replace("_", " ") |> String.capitalize()}
  </span>
  <%= if item.status == :submitted and item.review_note do %>
    <p class="mt-1 text-xs italic" style="color: var(--color-ribbon-red);">
      Revision requested: {item.review_note}
    </p>
  <% end %>
</div>
```

---

## 9. Authorization Checks

Add guards in `Kiroku.Access.Authorization`:

```elixir
# Reviewers and admins can start review / request revision
def can?(%User{role: role}, :review_item, _item) when role in [:reviewer, :admin], do: true
def can?(%User{role: :admin}, :approve_item, _item), do: true
def can?(%User{role: :admin}, :reject_item, _item), do: true

# A submitter can withdraw only their own item
def can?(%User{id: uid}, :withdraw_item, %Item{submitter_id: uid, status: s})
    when s in [:submitted, :under_review], do: true
def can?(%User{role: :admin}, :withdraw_item, _item), do: true

def can?(_user, _action, _target), do: false
```

Then in `ReviewLive`:

```elixir
unless Authorization.can?(reviewer, :review_item, item) do
  {:noreply, push_navigate(socket, to: ~p"/", replace: true)}
end
```

---

## 10. Oban Job Queue for Notifications

The `:notifications` queue (max_demand: 5) is already configured in `config.exs`.
`ReviewNotifier` uses `queue: :notifications` so review emails don't flood the system.

---

## 11. Migration Checklist

1. `mix ecto.gen.migration add_review_fields_to_items` — add `review_note`, `reviewed_by_id`, `reviewed_at`
2. `mix ecto.migrate`
3. `MIX_ENV=test mix ecto.migrate` — apply to test DB too

No changes to existing `bitstreams` or `items` columns are needed beyond the new review fields.
