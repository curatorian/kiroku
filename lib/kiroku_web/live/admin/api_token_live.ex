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

      <%!-- Create token form + token list --%>
      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <%!-- Left: create + list --%>
        <div class="lg:col-span-2 space-y-6">
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

        <%!-- Right: API documentation --%>
        <div class="lg:col-span-1 space-y-6">
          <div class="kiroku-card p-6 space-y-4">
            <div class="flex items-center gap-2">
              <.icon name="hero-book-open" class="w-5 h-5" style="color: var(--color-patchouli);" />
              <h2 class="font-heading text-lg font-semibold" style="color: var(--color-lilac);">
                API Reference
              </h2>
            </div>

            <div class="space-y-4 text-sm">
              <div>
                <h3
                  class="text-xs font-ui font-semibold uppercase tracking-wider mb-1"
                  style="color: var(--color-quill);"
                >
                  Authentication
                </h3>
                <p style="color: var(--color-wisteria);" class="leading-relaxed">
                  Pass the token via the
                  <code style="color: var(--color-ribbon-gold);">Authorization</code>
                  header or <code style="color: var(--color-ribbon-gold);">?token=</code>
                  query parameter:
                </p>
                <pre
                  phx-no-curly-interpolation
                  class="mt-2 text-xs font-mono p-3 rounded-lg overflow-x-auto"
                  style="background: var(--color-void); color: var(--color-lavender); border: 1px solid rgba(155,126,200,0.08);"
                ><code>Authorization: Bearer kiroku_...</code></pre>
                <pre
                  phx-no-curly-interpolation
                  class="mt-2 text-xs font-mono p-3 rounded-lg overflow-x-auto"
                  style="background: var(--color-void); color: var(--color-lavender); border: 1px solid rgba(155,126,200,0.08);"
                ><code>/api/v1/items?token=kiroku_...</code></pre>
              </div>

              <div class="pt-2" style="border-top: 1px solid rgba(155,126,200,0.08);">
                <h3
                  class="text-xs font-ui font-semibold uppercase tracking-wider mb-2"
                  style="color: var(--color-quill);"
                >
                  Endpoints
                </h3>
                <div class="space-y-3">
                  <div>
                    <div class="flex items-center gap-2 mb-1">
                      <span
                        class="text-xs font-mono font-bold px-1.5 py-0.5 rounded"
                        style="background: color-mix(in srgb, green 20%, transparent); color: #6bbd6b;"
                      >
                        GET
                      </span>
                      <code class="text-xs font-mono" style="color: var(--color-lavender);">
                        /api/v1/communities
                      </code>
                    </div>
                    <p class="text-xs ml-7" style="color: var(--color-quill);">
                      List all communities
                    </p>
                  </div>
                  <div>
                    <div class="flex items-center gap-2 mb-1">
                      <span
                        class="text-xs font-mono font-bold px-1.5 py-0.5 rounded"
                        style="background: color-mix(in srgb, green 20%, transparent); color: #6bbd6b;"
                      >
                        GET
                      </span>
                      <code class="text-xs font-mono" style="color: var(--color-lavender);">
                        /api/v1/communities/:id
                      </code>
                    </div>
                    <p class="text-xs ml-7" style="color: var(--color-quill);">
                      Community detail + collections
                    </p>
                  </div>
                  <div>
                    <div class="flex items-center gap-2 mb-1">
                      <span
                        class="text-xs font-mono font-bold px-1.5 py-0.5 rounded"
                        style="background: color-mix(in srgb, green 20%, transparent); color: #6bbd6b;"
                      >
                        GET
                      </span>
                      <code class="text-xs font-mono" style="color: var(--color-lavender);">
                        /api/v1/collections
                      </code>
                    </div>
                    <p class="text-xs ml-7" style="color: var(--color-quill);">
                      List collections (filter: ?community_id=)
                    </p>
                  </div>
                  <div>
                    <div class="flex items-center gap-2 mb-1">
                      <span
                        class="text-xs font-mono font-bold px-1.5 py-0.5 rounded"
                        style="background: color-mix(in srgb, green 20%, transparent); color: #6bbd6b;"
                      >
                        GET
                      </span>
                      <code class="text-xs font-mono" style="color: var(--color-lavender);">
                        /api/v1/items
                      </code>
                    </div>
                    <p class="text-xs ml-7" style="color: var(--color-quill);">
                      Search published items
                    </p>
                  </div>
                  <div>
                    <div class="flex items-center gap-2 mb-1">
                      <span
                        class="text-xs font-mono font-bold px-1.5 py-0.5 rounded"
                        style="background: color-mix(in srgb, green 20%, transparent); color: #6bbd6b;"
                      >
                        GET
                      </span>
                      <code class="text-xs font-mono" style="color: var(--color-lavender);">
                        /api/v1/items/:id
                      </code>
                    </div>
                    <p class="text-xs ml-7" style="color: var(--color-quill);">
                      Item detail with full metadata
                    </p>
                  </div>
                  <div>
                    <div class="flex items-center gap-2 mb-1">
                      <span
                        class="text-xs font-mono font-bold px-1.5 py-0.5 rounded"
                        style="background: color-mix(in srgb, green 20%, transparent); color: #6bbd6b;"
                      >
                        GET
                      </span>
                      <code class="text-xs font-mono" style="color: var(--color-lavender);">
                        /api/v1/items/:id/bitstreams
                      </code>
                    </div>
                    <p class="text-xs ml-7" style="color: var(--color-quill);">List item files</p>
                  </div>
                </div>
              </div>

              <div class="pt-2" style="border-top: 1px solid rgba(155,126,200,0.08);">
                <h3
                  class="text-xs font-ui font-semibold uppercase tracking-wider mb-2"
                  style="color: var(--color-quill);"
                >
                  Query Parameters
                  <span class="ml-1 normal-case font-normal" style="color: var(--color-dust);">
                    for /api/v1/items
                  </span>
                </h3>
                <div class="space-y-1.5">
                  <div class="flex items-baseline gap-2 text-xs">
                    <code
                      class="font-mono font-semibold flex-shrink-0"
                      style="color: var(--color-ribbon-gold); min-width: 4.5rem;"
                    >
                      q
                    </code>
                    <span style="color: var(--color-wisteria);">
                      Full-text search across title, abstract, keywords
                    </span>
                  </div>
                  <div class="flex items-baseline gap-2 text-xs">
                    <code
                      class="font-mono font-semibold flex-shrink-0"
                      style="color: var(--color-ribbon-gold); min-width: 4.5rem;"
                    >
                      type
                    </code>
                    <span style="color: var(--color-wisteria);">
                      Item type: skripsi, tesis, disertasi, tugas-akhir
                    </span>
                  </div>
                  <div class="flex items-baseline gap-2 text-xs">
                    <code
                      class="font-mono font-semibold flex-shrink-0"
                      style="color: var(--color-ribbon-gold); min-width: 4.5rem;"
                    >
                      faculty
                    </code>
                    <span style="color: var(--color-wisteria);">Filter by faculty name</span>
                  </div>
                  <div class="flex items-baseline gap-2 text-xs">
                    <code
                      class="font-mono font-semibold flex-shrink-0"
                      style="color: var(--color-ribbon-gold); min-width: 4.5rem;"
                    >
                      department
                    </code>
                    <span style="color: var(--color-wisteria);">
                      Filter by department / program study
                    </span>
                  </div>
                  <div class="flex items-baseline gap-2 text-xs">
                    <code
                      class="font-mono font-semibold flex-shrink-0"
                      style="color: var(--color-ribbon-gold); min-width: 4.5rem;"
                    >
                      year
                    </code>
                    <span style="color: var(--color-wisteria);">
                      Filter by publication year (e.g. 2024)
                    </span>
                  </div>
                  <div class="flex items-baseline gap-2 text-xs">
                    <code
                      class="font-mono font-semibold flex-shrink-0"
                      style="color: var(--color-ribbon-gold); min-width: 4.5rem;"
                    >
                      collection_id
                    </code>
                    <span style="color: var(--color-wisteria);">Filter by collection UUID</span>
                  </div>
                  <div class="flex items-baseline gap-2 text-xs">
                    <code
                      class="font-mono font-semibold flex-shrink-0"
                      style="color: var(--color-ribbon-gold); min-width: 4.5rem;"
                    >
                      page
                    </code>
                    <span style="color: var(--color-wisteria);">Page number (default: 1)</span>
                  </div>
                  <div class="flex items-baseline gap-2 text-xs">
                    <code
                      class="font-mono font-semibold flex-shrink-0"
                      style="color: var(--color-ribbon-gold); min-width: 4.5rem;"
                    >
                      per_page
                    </code>
                    <span style="color: var(--color-wisteria);">
                      Results per page (default: 20, max: 100)
                    </span>
                  </div>
                </div>
                <div class="flex items-baseline gap-2 text-xs mt-1.5">
                  <code
                    class="font-mono font-semibold flex-shrink-0"
                    style="color: var(--color-ribbon-gold); min-width: 4.5rem;"
                  >
                    community_id
                  </code>
                  <span style="color: var(--color-wisteria);">
                    Filter collections by community UUID (collections endpoint only)
                  </span>
                </div>
              </div>

              <div class="pt-2" style="border-top: 1px solid rgba(155,126,200,0.08);">
                <h3
                  class="text-xs font-ui font-semibold uppercase tracking-wider mb-2"
                  style="color: var(--color-quill);"
                >
                  Example Queries
                </h3>
                <div class="space-y-2">
                  <p class="text-xs font-ui" style="color: var(--color-dust);">
                    Search for "machine learning":
                  </p>
                  <pre
                    phx-no-curly-interpolation
                    class="text-xs font-mono p-2.5 rounded-lg overflow-x-auto"
                    style="background: var(--color-void); color: var(--color-lavender); border: 1px solid rgba(155,126,200,0.08);"
                  ><code>curl -H "Authorization: Bearer kiroku_..." /api/v1/items?q=machine+learning</code></pre>
                  <p class="text-xs font-ui pt-1" style="color: var(--color-dust);">
                    All skripsi from 2024, page 2:
                  </p>
                  <pre
                    phx-no-curly-interpolation
                    class="text-xs font-mono p-2.5 rounded-lg overflow-x-auto"
                    style="background: var(--color-void); color: var(--color-lavender); border: 1px solid rgba(155,126,200,0.08);"
                  ><code>curl -H "Authorization: Bearer kiroku_..." "/api/v1/items?type=skripsi&amp;year=2024&amp;page=2&amp;per_page=50"</code></pre>
                  <p class="text-xs font-ui pt-1" style="color: var(--color-dust);">
                    Token via query param (browser testing):
                  </p>
                  <pre
                    phx-no-curly-interpolation
                    class="text-xs font-mono p-2.5 rounded-lg overflow-x-auto"
                    style="background: var(--color-void); color: var(--color-lavender); border: 1px solid rgba(155,126,200,0.08);"
                  ><code>/api/v1/items?token=kiroku_...&amp;q=machine</code></pre>
                </div>
              </div>

              <div class="pt-2" style="border-top: 1px solid rgba(155,126,200,0.08);">
                <h3
                  class="text-xs font-ui font-semibold uppercase tracking-wider mb-1"
                  style="color: var(--color-quill);"
                >
                  Open Endpoints (no token)
                </h3>
                <div class="space-y-1.5 text-xs">
                  <div class="flex items-center gap-2">
                    <span
                      class="font-mono font-bold px-1.5 py-0.5 rounded"
                      style="background: color-mix(in srgb, green 20%, transparent); color: #6bbd6b;"
                    >
                      GET
                    </span>
                    <code class="font-mono" style="color: var(--color-lavender);">/health</code>
                  </div>
                  <div class="flex items-center gap-2">
                    <span
                      class="font-mono font-bold px-1.5 py-0.5 rounded"
                      style="background: color-mix(in srgb, green 20%, transparent); color: #6bbd6b;"
                    >
                      GET
                    </span>
                    <code class="font-mono" style="color: var(--color-lavender);">
                      /oai?verb=Identify
                    </code>
                  </div>
                </div>
              </div>
            </div>
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
