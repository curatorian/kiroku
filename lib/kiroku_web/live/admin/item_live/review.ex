defmodule KirokuWeb.Admin.ItemLive.Review do
  use KirokuWeb, :live_view

  alias Kiroku.Repository

  def mount(%{"id" => id}, _session, socket) do
    item =
      Repository.get_item!(id)
      |> Kiroku.Repo.preload([:submitter, :reviewed_by, :bitstreams])

    review_form =
      to_form(%{"review_action" => "approve", "review_note" => ""}, as: :review)

    {:ok,
     socket
     |> assign(:item, item)
     |> assign(:review_form, review_form)
     |> stream(:bitstreams, item.bitstreams)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_user}>
      <div class="max-w-4xl mx-auto space-y-6">
        <%!-- Breadcrumb --%>
        <div class="flex items-center gap-3">
          <.link
            navigate={~p"/admin/items"}
            class="text-sm transition-colors"
            style="color: var(--color-lavender);"
          >
            ← Items
          </.link>
          <span class="text-xs" style="color: var(--color-wisteria);">/</span>
          <span class="text-sm" style="color: var(--color-quill);">Review</span>
        </div>

        <%!-- Item details --%>
        <div class="kiroku-card p-6 space-y-4">
          <div class="flex items-center gap-3">
            <span class="badge-item-type">{@item.item_type}</span>
            <span class={["status-badge", to_string(@item.status)]}>{@item.status}</span>
          </div>

          <h1 class="font-heading text-2xl" style="color: var(--color-lilac);">{@item.title}</h1>
          <p class="kiroku-handle">{@item.handle || @item.id}</p>

          <%= if @item.abstract do %>
            <div>
              <p class="text-xs font-medium mb-1" style="color: var(--color-wisteria);">Abstract</p>
              <p class="text-sm leading-relaxed" style="color: var(--color-quill);">
                {@item.abstract}
              </p>
            </div>
          <% end %>

          <div class="grid grid-cols-2 gap-4 text-sm" style="color: var(--color-quill);">
            <%= if @item.submitter do %>
              <div>
                <span class="font-medium" style="color: var(--color-wisteria);">Submitted by:</span>
                {@item.submitter.display_name || @item.submitter.email}
              </div>
            <% end %>
            <%= if @item.submitted_at do %>
              <div>
                <span class="font-medium" style="color: var(--color-wisteria);">Submitted at:</span>
                {Calendar.strftime(@item.submitted_at, "%d %b %Y %H:%M")}
              </div>
            <% end %>
            <%= if @item.review_note do %>
              <div class="col-span-2">
                <span class="font-medium" style="color: var(--color-wisteria);">
                  Previous review note:
                </span>
                <p class="mt-1 italic">{@item.review_note}</p>
              </div>
            <% end %>
          </div>
        </div>

        <%!-- Bitstreams --%>
        <div class="kiroku-card p-5 space-y-3">
          <h3 class="font-heading text-lg" style="color: var(--color-lilac);">Files</h3>
          <div id="bitstreams" phx-update="stream" class="space-y-2">
            <div class="hidden only:block text-sm" style="color: var(--color-wisteria);">
              No files attached.
            </div>
            <div
              :for={{dom_id, bs} <- @streams.bitstreams}
              id={dom_id}
              class="flex items-center gap-3 text-sm py-2 border-b"
              style="border-color: rgba(255,255,255,0.05);"
            >
              <span class="badge-item-type text-xs">{bs.bundle_name}</span>
              <span style="color: var(--color-quill);">{bs.filename}</span>
              <span class="text-xs ml-auto" style="color: var(--color-wisteria);">
                {bs.access_level}
              </span>
              <.link
                href={~p"/items/#{@item.id}/bitstreams/#{bs.id}"}
                target="_blank"
                class="text-xs underline"
                style="color: var(--color-lavender);"
              >
                View
              </.link>
            </div>
          </div>
        </div>

        <%!-- Review action panel --%>
        <%= if @item.status in [:submitted, :under_review] do %>
          <div class="kiroku-card p-6 space-y-5">
            <h3 class="font-heading text-lg" style="color: var(--color-lilac);">Review Decision</h3>

            <%= if @item.status == :submitted do %>
              <button
                id="btn-start-review"
                phx-click="start_review"
                class="px-4 py-2 rounded-lg text-sm font-medium transition-all"
                style="background: rgba(123,104,238,0.2); color: var(--color-lavender); border: 1px solid rgba(123,104,238,0.35);"
              >
                Start Review
              </button>
            <% end %>

            <.form
              for={@review_form}
              id="review-form"
              phx-submit="submit_review"
              class="space-y-4"
            >
              <div class="flex flex-wrap gap-3">
                <label class="flex items-center gap-2 cursor-pointer">
                  <input
                    type="radio"
                    name="review[review_action]"
                    value="approve"
                    checked={@review_form[:review_action].value == "approve"}
                    class="accent-green-500"
                  />
                  <span class="text-sm" style="color: var(--color-quill);">Approve & Publish</span>
                </label>
                <label class="flex items-center gap-2 cursor-pointer">
                  <input
                    type="radio"
                    name="review[review_action]"
                    value="revision"
                    checked={@review_form[:review_action].value == "revision"}
                    class="accent-yellow-500"
                  />
                  <span class="text-sm" style="color: var(--color-quill);">Request Revision</span>
                </label>
                <label class="flex items-center gap-2 cursor-pointer">
                  <input
                    type="radio"
                    name="review[review_action]"
                    value="reject"
                    checked={@review_form[:review_action].value == "reject"}
                    class="accent-red-500"
                  />
                  <span class="text-sm" style="color: var(--color-quill);">Reject</span>
                </label>
              </div>

              <.input
                field={@review_form[:review_note]}
                type="textarea"
                label="Note (required for revision / reject)"
                placeholder="Leave feedback for the submitter…"
                rows="4"
              />

              <button
                type="submit"
                id="btn-submit-review"
                class="px-5 py-2 rounded-lg text-sm font-medium transition-all"
                style="background: rgba(123,104,238,0.3); color: var(--color-lilac); border: 1px solid rgba(123,104,238,0.5);"
              >
                Submit Decision
              </button>
            </.form>
          </div>
        <% end %>

        <%!-- Withdraw button (always available to admin for published items) --%>
        <%= if @item.status == :published do %>
          <div class="kiroku-card p-5">
            <button
              id="btn-withdraw"
              phx-click="withdraw"
              data-confirm="Withdraw this published item?"
              class="px-4 py-2 rounded-lg text-sm font-medium"
              style="background: rgba(196,65,90,0.12); color: var(--color-ribbon-red); border: 1px solid rgba(196,65,90,0.2);"
            >
              Withdraw
            </button>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  def handle_event("start_review", _params, socket) do
    item = socket.assigns.item
    reviewer = socket.assigns.current_user

    case Repository.start_review(item, reviewer) do
      {:ok, updated_item} ->
        {:noreply,
         socket
         |> assign(
           :item,
           Kiroku.Repo.preload(updated_item, [:submitter, :reviewed_by, :bitstreams])
         )
         |> put_flash(:info, "Review started.")}

      {:error, :invalid_transition} ->
        {:noreply, put_flash(socket, :error, "Cannot start review from this status.")}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, "Error: #{inspect(changeset.errors)}")}
    end
  end

  def handle_event("submit_review", %{"review" => params}, socket) do
    item = socket.assigns.item
    reviewer = socket.assigns.current_user
    action = params["review_action"]
    note = params["review_note"]

    result =
      case action do
        "approve" ->
          Repository.approve_item(item, reviewer)

        "revision" ->
          if String.trim(note || "") == "" do
            {:validation_error, "A note is required when requesting revision."}
          else
            Repository.request_revision(item, reviewer, note)
          end

        "reject" ->
          if String.trim(note || "") == "" do
            {:validation_error, "A note is required when rejecting."}
          else
            Repository.reject_item(item, reviewer, note)
          end

        _ ->
          {:error, :unknown_action}
      end

    case result do
      {:ok, updated_item} ->
        loaded = Kiroku.Repo.preload(updated_item, [:submitter, :reviewed_by, :bitstreams])

        {:noreply,
         socket
         |> assign(:item, loaded)
         |> stream(:bitstreams, loaded.bitstreams, reset: true)
         |> put_flash(:info, action_message(action))}

      {:validation_error, msg} ->
        {:noreply, put_flash(socket, :error, msg)}

      {:error, :invalid_transition} ->
        {:noreply,
         put_flash(socket, :error, "This action is not allowed from the current status.")}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, "Error: #{inspect(changeset.errors)}")}
    end
  end

  def handle_event("withdraw", _params, socket) do
    case Repository.withdraw_item_fsm(socket.assigns.item) do
      {:ok, updated_item} ->
        loaded = Kiroku.Repo.preload(updated_item, [:submitter, :reviewed_by, :bitstreams])
        {:noreply, socket |> assign(:item, loaded) |> put_flash(:info, "Item withdrawn.")}

      {:error, :invalid_transition} ->
        {:noreply, put_flash(socket, :error, "Cannot withdraw from this status.")}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, "Error: #{inspect(changeset.errors)}")}
    end
  end

  defp action_message("approve"), do: "Item approved and published."
  defp action_message("revision"), do: "Revision requested. Submitter has been notified."
  defp action_message("reject"), do: "Item rejected."
  defp action_message(_), do: "Decision recorded."
end
