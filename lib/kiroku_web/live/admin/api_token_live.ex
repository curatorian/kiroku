defmodule KirokuWeb.Admin.ApiTokenLive do
  use KirokuWeb, :live_view

  alias Kiroku.ApiTokens

  @impl true
  def mount(_params, _session, socket) do
    if superadmin?(socket) do
      socket =
        socket
        |> assign(:page_title, "API Tokens")
        |> assign(:tokens, load_tokens(socket))
        |> assign(:new_token_name, "")
        |> assign(:created_token, nil)
        |> assign(:confirm_delete, nil)
        |> assign(:confirm_rotate, nil)

      {:ok, socket}
    else
      {:ok,
       socket
       |> put_flash(:error, "You do not have access to this page.")
       |> redirect(to: ~p"/admin")}
    end
  end

  defp superadmin?(socket) do
    user = socket.assigns[:current_user]
    user && user.user_type == :superadmin
  end

  defp load_tokens(socket) do
    case socket.assigns[:current_user] do
      nil -> []
      user -> ApiTokens.list_tokens(user.id)
    end
  end

  # ── Events ─────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("save", %{"token" => %{"name" => name}}, socket) do
    name = String.trim(name)

    if name == "" do
      {:noreply, put_flash(socket, :error, "Token name is required.")}
    else
      case ApiTokens.create_token(socket.assigns.current_user, name) do
        {:ok, raw_token, api_token} ->
          {:noreply,
           socket
           |> assign(:tokens, [api_token | socket.assigns.tokens])
           |> assign(:created_token, raw_token)
           |> assign(:new_token_name, "")
           |> put_flash(:info, "Token created. Copy it now — it won't be shown again.")}

        {:error, changeset} ->
          {:noreply,
           put_flash(socket, :error, "Failed to create token: #{inspect(changeset.errors)}")}
      end
    end
  end

  def handle_event("cancel_created", _, socket) do
    {:noreply, assign(socket, :created_token, nil)}
  end

  def handle_event("validate", %{"token" => %{"name" => name}}, socket) do
    {:noreply, assign(socket, :new_token_name, name)}
  end

  def handle_event("request_rotate", %{"id" => token_id}, socket) do
    {:noreply, assign(socket, :confirm_rotate, token_id)}
  end

  def handle_event("cancel_rotate", _, socket) do
    {:noreply, assign(socket, :confirm_rotate, nil)}
  end

  def handle_event("confirm_rotate", %{"id" => token_id}, socket) do
    case ApiTokens.rotate_token(token_id) do
      {:ok, raw_token, _api_token} ->
        {:noreply,
         socket
         |> assign(:tokens, load_tokens(socket))
         |> assign(:confirm_rotate, nil)
         |> assign(:created_token, raw_token)
         |> put_flash(:info, "Token rotated. Copy the new token now — it won't be shown again.")}

      {:error, :not_found} ->
        {:noreply,
         socket |> assign(:confirm_rotate, nil) |> put_flash(:error, "Token not found.")}
    end
  end

  def handle_event("request_delete", %{"id" => token_id}, socket) do
    {:noreply, assign(socket, :confirm_delete, token_id)}
  end

  def handle_event("cancel_delete", _, socket) do
    {:noreply, assign(socket, :confirm_delete, nil)}
  end

  def handle_event("confirm_delete", %{"id" => token_id}, socket) do
    case ApiTokens.delete_token(token_id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:tokens, Enum.reject(socket.assigns.tokens, &(&1.id == token_id)))
         |> assign(:confirm_delete, nil)
         |> put_flash(:info, "Token deleted.")}

      {:error, :not_found} ->
        {:noreply,
         socket |> assign(:confirm_delete, nil) |> put_flash(:error, "Token not found.")}
    end
  end

  def handle_event("copy_token", _, socket) do
    {:noreply, put_flash(socket, :info, "Copied to clipboard.")}
  end

  # ── Render ─────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_user} page_title="API Tokens">
      <%!-- Created token banner (shown once after create/rotate) --%>
      <%= if @created_token do %>
        <div class="kiroku-card p-6 mb-6" style="border-color: var(--color-patchouli);">
          <div class="flex items-start gap-3">
            <div
              class="flex-shrink-0 w-10 h-10 rounded-lg flex items-center justify-center"
              style="background: color-mix(in srgb, var(--color-ribbon-gold) 20%, transparent);"
            >
              <.icon
                name="hero-exclamation-triangle"
                class="w-5 h-5"
                style="color: var(--color-ribbon-gold);"
              />
            </div>
            <div class="flex-1 min-w-0">
              <h3 class="font-heading text-lg font-semibold" style="color: var(--color-lilac);">
                Save your token now
              </h3>
              <p class="text-sm mt-1" style="color: var(--color-dust);">
                This token won't be shown again. Store it somewhere safe.
              </p>
              <div class="flex items-center gap-2 mt-3">
                <code
                  id="created-token-display"
                  class="flex-1 text-sm font-mono px-3 py-2 rounded-lg overflow-x-auto"
                  style="background: var(--color-void); color: var(--color-ribbon-gold); border: 1px solid rgba(155,126,200,0.12);"
                >
                  {@created_token}
                </code>
                <button
                  id="copy-token-btn"
                  phx-hook=".CopyToken"
                  data-token={@created_token}
                  class="flex-shrink-0 px-3 py-2 rounded-lg text-sm transition-colors"
                  style="background: var(--color-patchouli); color: white;"
                >
                  <.icon name="hero-clipboard-document" class="w-4 h-4" />
                </button>
              </div>
              <button
                phx-click="cancel_created"
                class="text-xs mt-3 transition-colors hover:text-patchouli"
                style="color: var(--color-dust);"
              >
                I've saved it — dismiss
              </button>
            </div>
          </div>
        </div>
      <% end %>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".CopyToken">
        export default {
          mounted() {
            this.el.addEventListener("click", () => {
              const token = this.el.dataset.token;
              navigator.clipboard.writeText(token);
              const icon = this.el.querySelector("span");
              if (icon) {
                const original = icon.className;
                icon.className = original.replace("hero-clipboard-document", "hero-check");
                setTimeout(() => { icon.className = original; }, 1500);
              }
            });
          }
        }
      </script>

      <%!-- Create token form + token list + API link --%>
      <div class="space-y-6">
        <%!-- API Reference link --%>
        <.link
          navigate={~p"/admin/api-reference"}
          class="kiroku-card p-4 flex items-center gap-4 transition-all hover:brightness-110 group"
          style="border: 1px solid rgba(155,126,200,0.12);"
        >
          <div
            class="flex-shrink-0 w-10 h-10 rounded-lg flex items-center justify-center"
            style="background: color-mix(in srgb, var(--color-patchouli) 20%, transparent);"
          >
            <.icon name="hero-book-open" class="w-5 h-5" style="color: var(--color-patchouli);" />
          </div>
          <div class="flex-1 min-w-0">
            <h3 class="font-heading text-sm font-semibold" style="color: var(--color-lilac);">
              API Reference
            </h3>
            <p class="text-xs" style="color: var(--color-dust);">
              Full endpoint documentation with request/response examples
            </p>
          </div>
          <.icon
            name="hero-arrow-right"
            class="w-4 h-4 transition-transform group-hover:translate-x-1"
            style="color: var(--color-dust);"
          />
        </.link>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <%!-- Create form --%>
          <div class="kiroku-card p-6 space-y-4">
            <div class="flex items-center gap-2">
              <.icon name="hero-key" class="w-5 h-5" style="color: var(--color-patchouli);" />
              <h2 class="font-heading text-lg font-semibold" style="color: var(--color-lilac);">
                Create New Token
              </h2>
            </div>
            <.form
              for={to_form(%{"name" => @new_token_name}, as: :token)}
              id="token-create-form"
              phx-submit="save"
              phx-change="validate"
            >
              <div class="flex items-end gap-3">
                <div class="flex-1">
                  <.input
                    field={to_form(%{"name" => @new_token_name}, as: :token)[:name]}
                    type="text"
                    label="Token name"
                    placeholder="e.g. Postman, CI/CD, Data Harvester"
                  />
                </div>
                <button
                  type="submit"
                  class="flex items-center gap-1.5 px-4 py-2 rounded-lg font-medium text-sm transition-all hover:brightness-110 active:scale-95"
                  style="background: var(--color-patchouli); color: white;"
                >
                  <.icon name="hero-plus" class="w-4 h-4" /> Generate
                </button>
              </div>
            </.form>
          </div>

          <%!-- Token list --%>
          <div class="kiroku-card p-6 space-y-4">
            <div class="flex items-center gap-2">
              <.icon name="hero-list-bullet" class="w-5 h-5" style="color: var(--color-patchouli);" />
              <h2 class="font-heading text-lg font-semibold" style="color: var(--color-lilac);">
                Active Tokens ({length(@tokens)})
              </h2>
            </div>

            <%= if @tokens == [] do %>
              <div class="text-center py-8">
                <.icon
                  name="hero-key"
                  class="w-10 h-10 mx-auto opacity-30"
                  style="color: var(--color-dust);"
                />
                <p class="text-sm mt-3" style="color: var(--color-dust);">
                  No API tokens yet. Create one above to get started.
                </p>
              </div>
            <% else %>
              <div class="space-y-3">
                <div
                  :for={token <- @tokens}
                  id={"token-#{token.id}"}
                  class="rounded-lg p-4 flex items-center justify-between gap-4"
                  style="background: var(--color-void); border: 1px solid rgba(155,126,200,0.08);"
                >
                  <div class="min-w-0 flex-1">
                    <div class="flex items-center gap-2">
                      <.icon
                        name="hero-key"
                        class="w-4 h-4 flex-shrink-0"
                        style="color: var(--color-lavender);"
                      />
                      <span class="font-medium text-sm truncate" style="color: var(--color-lilac);">
                        {token.name}
                      </span>
                    </div>
                    <div
                      class="flex flex-wrap items-center gap-x-4 gap-y-1 mt-1.5 text-xs"
                      style="color: var(--color-quill);"
                    >
                      <span>Created {format_date(token.inserted_at)}</span>
                      <span :if={token.last_used_at}>
                        Last used {format_date(token.last_used_at)}
                      </span>
                      <span :if={!token.last_used_at}>
                        Never used
                      </span>
                    </div>
                  </div>

                  <div class="flex items-center gap-2 flex-shrink-0">
                    <%= if @confirm_rotate == token.id do %>
                      <span class="text-xs" style="color: var(--color-ribbon-amber);">Replace?</span>
                      <button
                        phx-click="confirm_rotate"
                        phx-value-id={token.id}
                        class="px-2.5 py-1 rounded text-xs font-medium transition-colors"
                        style="background: var(--color-ribbon-red); color: white;"
                      >
                        Yes
                      </button>
                      <button
                        phx-click="cancel_rotate"
                        class="px-2.5 py-1 rounded text-xs transition-colors hover:bg-base-300"
                        style="color: var(--color-dust);"
                      >
                        No
                      </button>
                    <% else %>
                      <button
                        phx-click="request_rotate"
                        phx-value-id={token.id}
                        title="Rotate token"
                        class="p-1.5 rounded-lg transition-colors hover:bg-base-300"
                        style="color: var(--color-dust);"
                      >
                        <.icon name="hero-arrow-path" class="w-4 h-4" />
                      </button>
                    <% end %>

                    <%= if @confirm_delete == token.id do %>
                      <span class="text-xs" style="color: var(--color-ribbon-red);">Delete?</span>
                      <button
                        phx-click="confirm_delete"
                        phx-value-id={token.id}
                        class="px-2.5 py-1 rounded text-xs font-medium transition-colors"
                        style="background: var(--color-ribbon-red); color: white;"
                      >
                        Yes
                      </button>
                      <button
                        phx-click="cancel_delete"
                        class="px-2.5 py-1 rounded text-xs transition-colors hover:bg-base-300"
                        style="color: var(--color-dust);"
                      >
                        No
                      </button>
                    <% else %>
                      <button
                        phx-click="request_delete"
                        phx-value-id={token.id}
                        title="Delete token"
                        class="p-1.5 rounded-lg transition-colors hover:bg-base-300"
                        style="color: var(--color-dust);"
                      >
                        <.icon name="hero-trash" class="w-4 h-4" />
                      </button>
                    <% end %>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </Layouts.admin>
    """
  end

  defp format_date(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y")
  end
end
