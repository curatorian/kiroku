defmodule KirokuWeb.Admin.ApiReferenceLive do
  use KirokuWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    if superadmin?(socket) do
      {:ok,
       socket
       |> assign(:page_title, "API Reference")
       |> assign(:expanded, %{})}
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

  @impl true
  def handle_event("toggle", %{"id" => id}, socket) do
    expanded = Map.update(socket.assigns.expanded, id, false, &(!&1))
    {:noreply, assign(socket, :expanded, expanded)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_user} page_title="API Reference">
      <div class="space-y-8">
        <div class="kiroku-card p-6">
          <div class="flex items-center gap-3 mb-3">
            <div
              class="w-10 h-10 rounded-lg flex items-center justify-center"
              style="background: color-mix(in srgb, var(--color-patchouli) 20%, transparent);"
            >
              <.icon name="hero-book-open" class="w-5 h-5" style="color: var(--color-patchouli);" />
            </div>
            <div>
              <h2 class="font-heading text-xl font-semibold" style="color: var(--color-lilac);">
                REST API v1
              </h2>
              <p class="text-sm" style="color: var(--color-dust);">
                Base URL:
                <code class="font-mono" style="color: var(--color-ribbon-gold);">
                  {origin()}/api/v1
                </code>
              </p>
            </div>
          </div>
        </div>

        <div class="kiroku-card p-6 space-y-4">
          <div class="flex items-center gap-2">
            <.icon name="hero-lock-closed" class="w-5 h-5" style="color: var(--color-patchouli);" />
            <h3 class="font-heading text-lg font-semibold" style="color: var(--color-lilac);">
              Authentication
            </h3>
          </div>
          <p class="text-sm" style="color: var(--color-wisteria);">
            All API endpoints require authentication. Pass your API token via the
            <code style="color: var(--color-ribbon-gold);">Authorization</code>
            header or <code style="color: var(--color-ribbon-gold);">?token=</code>
            query parameter.
          </p>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div
              class="rounded-lg p-4"
              style="background: var(--color-void); border: 1px solid rgba(155,126,200,0.08);"
            >
              <p
                class="text-xs font-ui font-semibold uppercase tracking-wider mb-2"
                style="color: var(--color-quill);"
              >
                Header (Recommended)
              </p>
              <pre
                phx-no-curly-interpolation
                class="text-xs font-mono p-3 rounded-lg"
                style="background: var(--color-grimoire); color: var(--color-lavender);"
              ><code>Authorization: Bearer kiroku_abc123...</code></pre>
            </div>
            <div
              class="rounded-lg p-4"
              style="background: var(--color-void); border: 1px solid rgba(155,126,200,0.08);"
            >
              <p
                class="text-xs font-ui font-semibold uppercase tracking-wider mb-2"
                style="color: var(--color-quill);"
              >
                Query Parameter
              </p>
              <pre
                phx-no-curly-interpolation
                class="text-xs font-mono p-3 rounded-lg"
                style="background: var(--color-grimoire); color: var(--color-lavender);"
              ><code>/api/v1/items?token=kiroku_abc123...</code></pre>
            </div>
          </div>
        </div>

        <div class="kiroku-card p-6 space-y-4">
          <div class="flex items-center gap-2">
            <.icon
              name="hero-building-library"
              class="w-5 h-5"
              style="color: var(--color-patchouli);"
            />
            <h3 class="font-heading text-lg font-semibold" style="color: var(--color-lilac);">
              Communities
            </h3>
          </div>
          {endpoint_card(assigns, %{
            id: "communities-list",
            method: "GET",
            path: "/communities",
            description: "List all active communities visible to the authenticated user.",
            params: [],
            response: %{status: "200 OK", body: communities_list_json()}
          })}
          {endpoint_card(assigns, %{
            id: "communities-show",
            method: "GET",
            path: "/communities/:id",
            description: "Retrieve a single community with its active collections.",
            params: [%{name: "id", type: "UUID", required: true, description: "Community UUID"}],
            response: %{status: "200 OK", body: communities_show_json()}
          })}
        </div>

        <div class="kiroku-card p-6 space-y-4">
          <div class="flex items-center gap-2">
            <.icon name="hero-folder-open" class="w-5 h-5" style="color: var(--color-patchouli);" />
            <h3 class="font-heading text-lg font-semibold" style="color: var(--color-lilac);">
              Collections
            </h3>
          </div>
          {endpoint_card(assigns, %{
            id: "collections-list",
            method: "GET",
            path: "/collections",
            description: "List all active collections. Optionally filter by community.",
            params: [
              %{
                name: "community_id",
                type: "UUID",
                required: false,
                description: "Filter by community UUID"
              }
            ],
            response: %{status: "200 OK", body: collections_list_json()}
          })}
          {endpoint_card(assigns, %{
            id: "collections-show",
            method: "GET",
            path: "/collections/:id",
            description: "Retrieve a single collection with item count and parent community.",
            params: [%{name: "id", type: "UUID", required: true, description: "Collection UUID"}],
            response: %{status: "200 OK", body: collections_show_json()}
          })}
        </div>

        <div class="kiroku-card p-6 space-y-4">
          <div class="flex items-center gap-2">
            <.icon name="hero-document-text" class="w-5 h-5" style="color: var(--color-patchouli);" />
            <h3 class="font-heading text-lg font-semibold" style="color: var(--color-lilac);">
              Items
            </h3>
          </div>
          {endpoint_card(assigns, %{
            id: "items-list",
            method: "GET",
            path: "/items",
            description: "Search and list published items with pagination.",
            params: [
              %{
                name: "q",
                type: "string",
                required: false,
                description: "Full-text search across title, abstract, keywords"
              },
              %{
                name: "type",
                type: "string",
                required: false,
                description: "Item type: skripsi, tesis, disertasi, tugas-akhir"
              },
              %{
                name: "faculty",
                type: "string",
                required: false,
                description: "Filter by faculty name"
              },
              %{
                name: "department",
                type: "string",
                required: false,
                description: "Filter by department / program study"
              },
              %{
                name: "year",
                type: "integer",
                required: false,
                description: "Filter by publication year (e.g. 2024)"
              },
              %{
                name: "collection_id",
                type: "UUID",
                required: false,
                description: "Filter by collection UUID"
              },
              %{
                name: "page",
                type: "integer",
                required: false,
                description: "Page number (default: 1)"
              },
              %{
                name: "per_page",
                type: "integer",
                required: false,
                description: "Results per page (default: 20, max: 100)"
              }
            ],
            response: %{status: "200 OK", body: items_list_json()}
          })}
          {endpoint_card(assigns, %{
            id: "items-show",
            method: "GET",
            path: "/items/:id",
            description: "Retrieve a single item with full metadata, relations, and keywords.",
            params: [%{name: "id", type: "UUID", required: true, description: "Item UUID"}],
            response: %{status: "200 OK", body: items_show_json()}
          })}
          {endpoint_card(assigns, %{
            id: "items-bitstreams",
            method: "GET",
            path: "/items/:id/bitstreams",
            description: "List accessible files (bitstreams) for an item.",
            params: [%{name: "id", type: "UUID", required: true, description: "Item UUID"}],
            response: %{status: "200 OK", body: bitstreams_list_json()}
          })}
          {endpoint_card(assigns, %{
            id: "items-create",
            method: "POST",
            path: "/items",
            description:
              "Create a new item with optional relations. The API user becomes the submitter.",
            params: [],
            body: items_create_body(),
            response: %{status: "201 Created", body: items_create_json()}
          })}
          {endpoint_card(assigns, %{
            id: "items-update",
            method: "PATCH",
            path: "/items/:id",
            description: "Update item metadata. Only provided fields are changed.",
            params: [%{name: "id", type: "UUID", required: true, description: "Item UUID"}],
            body: items_update_body(),
            response: %{status: "200 OK", body: items_update_json()}
          })}
          {endpoint_card(assigns, %{
            id: "items-deposit",
            method: "POST",
            path: "/items/:id/bitstreams",
            description: "Upload a file via multipart/form-data.",
            params: [%{name: "id", type: "UUID", required: true, description: "Item UUID"}],
            body: bitstreams_deposit_body(),
            response: %{status: "201 Created", body: bitstreams_deposit_json()}
          })}
          {endpoint_card(assigns, %{
            id: "items-full-deposit",
            method: "POST",
            path: "/items/deposit",
            description:
              "Full deposit: create an item with metadata, relations, and optional file uploads in a single request.",
            params: [],
            body: full_deposit_body(),
            response: %{status: "201 Created", body: full_deposit_json()}
          })}
        </div>

        <div class="kiroku-card p-6 space-y-4">
          <div class="flex items-center gap-2">
            <.icon name="hero-command-line" class="w-5 h-5" style="color: var(--color-patchouli);" />
            <h3 class="font-heading text-lg font-semibold" style="color: var(--color-lilac);">
              cURL Examples
            </h3>
          </div>
          <div class="space-y-4">
            {curl_example(assigns, %{
              id: "curl-list",
              title: "Search published items",
              command:
                "curl -H \"Authorization: Bearer kiroku_...\" /api/v1/items?q=machine+learning&type=skripsi&year=2024"
            })}
            {curl_example(assigns, %{
              id: "curl-show",
              title: "Get item detail",
              command: "curl -H \"Authorization: Bearer kiroku_...\" /api/v1/items/:id"
            })}
            {curl_example(assigns, %{
              id: "curl-create",
              title: "Create an item",
              command:
                "curl -X POST -H \"Authorization: Bearer kiroku_...\" -H \"Content-Type: application/json\" -d '{\"item\":{\"title\":\"Judul\",\"collection_id\":\"UUID\",\"item_type\":\"skripsi\"}}' /api/v1/items"
            })}
            {curl_example(assigns, %{
              id: "curl-upload",
              title: "Upload a file",
              command:
                "curl -X POST -H \"Authorization: Bearer kiroku_...\" -F \"file=@bab1.pdf\" -F \"bundle_name=CHAPTER\" /api/v1/items/:id/bitstreams"
            })}
            {curl_example(assigns, %{
              id: "curl-full-deposit",
              title: "Full deposit (item + files)",
              command:
                "curl -X POST -H \"Authorization: Bearer kiroku_...\" -F \"item[title]=Judul Skripsi\" -F \"item[collection_id]=UUID\" -F \"item[item_type]=skripsi\" -F \"relations[authors][0][author_name]=Penulis\" -F \"files[fulltext]=@skripsi.pdf\" /api/v1/items/deposit"
            })}
          </div>
        </div>

        <div class="kiroku-card p-6 space-y-4">
          <div class="flex items-center gap-2">
            <.icon name="hero-globe-alt" class="w-5 h-5" style="color: var(--color-patchouli);" />
            <h3 class="font-heading text-lg font-semibold" style="color: var(--color-lilac);">
              Open Endpoints
            </h3>
            <span
              class="text-xs px-2 py-0.5 rounded font-ui"
              style="background: color-mix(in srgb, green 15%, transparent); color: #6bbd6b;"
            >
              No auth required
            </span>
          </div>
          <div class="space-y-2">
            <div class="flex items-center gap-3">
              <span
                class="text-xs font-mono font-bold px-1.5 py-0.5 rounded"
                style="background: color-mix(in srgb, green 20%, transparent); color: #6bbd6b;"
              >
                GET
              </span>
              <code class="text-sm font-mono" style="color: var(--color-lavender);">/health</code>
              <span class="text-xs" style="color: var(--color-quill);">Health check endpoint</span>
            </div>
            <div class="flex items-center gap-3">
              <span
                class="text-xs font-mono font-bold px-1.5 py-0.5 rounded"
                style="background: color-mix(in srgb, green 20%, transparent); color: #6bbd6b;"
              >
                GET
              </span>
              <code class="text-sm font-mono" style="color: var(--color-lavender);">
                /oai?verb=Identify
              </code>
              <span class="text-xs" style="color: var(--color-quill);">
                OAI-PMH repository identification
              </span>
            </div>
          </div>
        </div>
      </div>
    </Layouts.admin>
    """
  end

  # ── JSON response bodies ────────────────────────────────────────────────

  defp communities_list_json,
    do:
      ~s({"data":[{"id":"a1b2c3d4-...","name":"Fakultas Teknik","handle":"ft","short_description":"Faculty of Engineering","description":"...","position":1,"inserted_at":"2024-01-15T08:30:00Z"}]})

  defp communities_show_json,
    do:
      ~s({"data":{"id":"a1b2c3d4-...","name":"Fakultas Teknik","handle":"ft","short_description":"Faculty of Engineering","description":"...","position":1,"inserted_at":"2024-01-15T08:30:00Z","collections":[{"id":"e5f6g7h8-...","name":"Skripsi","handle":"ft-skripsi","short_description":"Undergraduate theses"}]}})

  defp collections_list_json,
    do:
      ~s({"data":[{"id":"e5f6g7h8-...","name":"Skripsi","handle":"ft-skripsi","short_description":"Undergraduate theses","community_id":"a1b2c3d4-...","position":1,"inserted_at":"2024-01-15T09:00:00Z"}]})

  defp collections_show_json,
    do:
      ~s({"data":{"id":"e5f6g7h8-...","name":"Skripsi","handle":"ft-skripsi","short_description":"Undergraduate theses","community_id":"a1b2c3d4-...","position":1,"inserted_at":"2024-01-15T09:00:00Z","item_count":142,"community":{"id":"a1b2c3d4-...","name":"Fakultas Teknik","handle":"ft"}}})

  defp items_list_json,
    do:
      ~s({"data":[{"id":"i1j2k3l4-...","handle":"12345","title":"Analisis Sentimen pada Ulasan Aplikasi Mobile","item_type":"skripsi","student_name":"Ahmad Rizki","department":"Teknik Informatika","faculty":"Fakultas Teknik","publication_year":2024,"published_at":"2024-06-15T10:00:00Z","language":"id","access_level":"public"}]})

  defp items_show_json do
    ~s({"data":{"id":"i1j2k3l4-...","handle":"12345","title":"Analisis Sentimen pada Ulasan Aplikasi Mobile","title_alt":"Sentiment Analysis on Mobile App Reviews","item_type":"skripsi","student_name":"Ahmad Rizki","student_id":"1234567890","department":"Teknik Informatika","faculty":"Fakultas Teknik","institution":"Universitas Indonesia","degree_level":"S1","abstract":"...","publication_year":2024,"date_issued":"2024-06-15","language":"id","access_level":"public","status":"published","published_at":"2024-06-15T10:00:00Z","collection":{"id":"e5f6g7h8-...","name":"Skripsi","handle":"ft-skripsi"},"authors":[{"id":"...","name":"Ahmad Rizki","name_alt":"A. Rizki","affiliation":"Universitas Indonesia","email":"ahmad@ui.ac.id","orcid":"0000-0001-2345-6789","sequence":1}],"advisors":[{"id":"...","name":"Dr. Budi Santoso","name_alt":"B. Santoso","role":"main_advisor","affiliation":"Universitas Indonesia","nidn":"0012345678","sequence":1}],"keywords":["sentiment analysis","mobile apps","NLP"],"metadata_extras":[]}})
  end

  defp bitstreams_list_json,
    do:
      ~s({"data":[{"id":"...","filename":"bab1.pdf","bundle_name":"CHAPTER","sequence":1,"description":"Bab 1 - Pendahuluan","mime_type":"application/pdf","file_size":245760,"access_level":"inherit"}]})

  defp items_create_body do
    ~s({"item":{"title":"Judul Skripsi","collection_id":"e5f6g7h8-...","item_type":"skripsi","student_name":"Mahasiswa","student_id":"1234567890","faculty":"Fakultas Teknik","department":"Teknik Informatika","abstract":"Abstrak dalam Bahasa Indonesia...","language":"id","status":"submitted"},"relations":{"authors":[{"author_name":"Penulis Utama","sequence":1}],"advisors":[{"advisor_name":"Dr. Pembimbing","advisor_role":"main_advisor","sequence":1}],"keywords":["kata kunci 1","kata kunci 2"]}})
  end

  defp items_create_json,
    do:
      ~s({"data":{"id":"new-uuid-...","title":"Judul Skripsi","status":"submitted","...":"..."}})

  defp items_update_body,
    do: ~s({"item":{"title":"Updated Title","abstract":"Updated abstract..."}})

  defp items_update_json,
    do:
      ~s({"data":{"id":"i1j2k3l4-...","title":"Updated Title","abstract":"Updated abstract...","...":"..."}})

  defp bitstreams_deposit_body do
    ~s{Content-Type: multipart/form-data\n\nfile          (binary)  - The file to upload (required)\nbundle_name   (string)  - ORIGINAL | THUMBNAIL | CHAPTER | SUPPLEMENTAL | ADMINISTRATIVE | LICENSE | MEDIA | SOURCE\ndescription   (string)  - File description (e.g. "Bab 1 - Pendahuluan")\nsequence      (integer) - Sort order (default: 1)\naccess_level  (string)  - inherit | public | restricted | private}
  end

  defp bitstreams_deposit_json,
    do:
      ~s({"data":{"id":"...","filename":"bab1.pdf","bundle_name":"CHAPTER","sequence":1,"description":"Bab 1 - Pendahuluan","mime_type":"application/pdf","file_size":245760,"access_level":"inherit"}})

  defp full_deposit_body do
    """
    Content-Type: multipart/form-data

    item[title]           (string)  - Item title (required)
    item[collection_id]   (UUID)    - Target collection (required)
    item[item_type]       (string)  - skripsi, tesis, disertasi, tugas-akhir
    item[abstract]        (string)  - Abstract / summary
    item[student_name]    (string)  - Student author name
    item[status]          (string)  - draft (default), submitted

    relations[authors]      (array)   - List of author objects: author_name, sequence, affiliation, email, orcid
    relations[advisors]     (array)   - List of advisor objects: advisor_name, advisor_role, affiliation, nidn
    relations[keywords]     (array)   - List of keyword strings

    files[fulltext]       (binary)  - Full text PDF upload
    files[cover]          (binary)  - Cover image upload
    files[chapters]       (binary)  - Chapter file uploads (multiple allowed)
    """
  end

  defp full_deposit_json,
    do:
      ~s({"data":{"id":"new-uuid-...","title":"Judul Skripsi","status":"draft","item_type":"skripsi","collection":{"id":"...","name":"Skripsi","handle":"ft-skripsi"},"authors":[{"id":"...","name":"Penulis Utama","sequence":1}],"advisors":[],"keywords":["kata kunci"],"...":"..."}})

  # ── Component helpers ───────────────────────────────────────────────────

  defp endpoint_card(assigns, endpoint) do
    assigns =
      assigns
      |> Map.put(:endpoint, endpoint)
      |> Map.put_new(:expanded, %{})

    is_expanded = Map.get(assigns.expanded, endpoint.id, false)
    assigns = assign(assigns, :is_expanded, is_expanded)

    ~H"""
    <div
      class="rounded-lg overflow-hidden transition-all"
      style="border: 1px solid rgba(155,126,200,0.12);"
    >
      <button
        phx-click="toggle"
        phx-value-id={@endpoint.id}
        class="w-full flex items-center gap-3 px-4 py-3 text-left transition-colors"
        style={"background: var(--color-void);" <> if(@is_expanded, do: "border-bottom: 1px solid rgba(155,126,200,0.08);", else: "")}
      >
        <span class={method_badge_class(@endpoint.method)}>{@endpoint.method}</span>
        <code class="text-sm font-mono flex-1" style="color: var(--color-lavender);">
          {@endpoint.path}
        </code>
        <span class="text-xs hidden md:inline" style="color: var(--color-quill);">
          {@endpoint.description}
        </span>
        <.icon
          name={if(@is_expanded, do: "hero-chevron-up", else: "hero-chevron-down")}
          class="w-4 h-4 flex-shrink-0"
          style="color: var(--color-dust);"
        />
      </button>
      <%= if @is_expanded do %>
        <div class="px-4 py-4 space-y-4" style="background: var(--color-grimoire);">
          <p class="text-sm md:hidden" style="color: var(--color-wisteria);">
            {@endpoint.description}
          </p>
          <%= if @endpoint.params != [] do %>
            <div>
              <h4
                class="text-xs font-ui font-semibold uppercase tracking-wider mb-2"
                style="color: var(--color-quill);"
              >
                Parameters
              </h4>
              <div
                class="rounded-lg overflow-hidden"
                style="border: 1px solid rgba(155,126,200,0.08);"
              >
                <table class="w-full text-xs">
                  <thead>
                    <tr style="background: var(--color-void);">
                      <th
                        class="px-3 py-2 text-left font-ui font-semibold"
                        style="color: var(--color-quill);"
                      >
                        Name
                      </th>
                      <th
                        class="px-3 py-2 text-left font-ui font-semibold"
                        style="color: var(--color-quill);"
                      >
                        Type
                      </th>
                      <th
                        class="px-3 py-2 text-left font-ui font-semibold"
                        style="color: var(--color-quill);"
                      >
                        Required
                      </th>
                      <th
                        class="px-3 py-2 text-left font-ui font-semibold"
                        style="color: var(--color-quill);"
                      >
                        Description
                      </th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr
                      :for={param <- @endpoint.params}
                      style="border-top: 1px solid rgba(155,126,200,0.06);"
                    >
                      <td
                        class="px-3 py-2 font-mono font-semibold"
                        style="color: var(--color-ribbon-gold);"
                      >
                        {param.name}
                      </td>
                      <td class="px-3 py-2 font-mono" style="color: var(--color-lavender);">
                        {param.type}
                      </td>
                      <td class="px-3 py-2">
                        <%= if param.required do %>
                          <span class="text-xs font-bold" style="color: var(--color-ribbon-red);">
                            required
                          </span>
                        <% else %>
                          <span class="text-xs" style="color: var(--color-dust);">optional</span>
                        <% end %>
                      </td>
                      <td class="px-3 py-2" style="color: var(--color-wisteria);">
                        {param.description}
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>
          <% end %>
          <%= if @endpoint[:body] do %>
            <div>
              <h4
                class="text-xs font-ui font-semibold uppercase tracking-wider mb-2"
                style="color: var(--color-quill);"
              >
                Request Body
              </h4>
              <pre
                phx-no-curly-interpolation
                class="text-xs font-mono p-4 rounded-lg overflow-x-auto"
                style="background: var(--color-void); color: var(--color-lavender); border: 1px solid rgba(155,126,200,0.08);"
              ><code><%= @endpoint.body %></code></pre>
            </div>
          <% end %>
          <div>
            <h4
              class="text-xs font-ui font-semibold uppercase tracking-wider mb-2"
              style="color: var(--color-quill);"
            >
              Response
            </h4>
            <div class="flex items-center gap-2 mb-2">
              <span class={"text-xs font-mono font-bold px-2 py-0.5 rounded #{response_status_class(@endpoint.response.status)}"}>
                {@endpoint.response.status}
              </span>
              <span class="text-xs" style="color: var(--color-dust);">application/json</span>
            </div>
            <pre
              phx-no-curly-interpolation
              class="text-xs font-mono p-4 rounded-lg overflow-x-auto"
              style="background: var(--color-void); color: var(--color-lavender); border: 1px solid rgba(155,126,200,0.08);"
            ><code><%= @endpoint.response.body %></code></pre>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp curl_example(assigns, example) do
    assigns = assign(assigns, :example, example)
    is_expanded = Map.get(assigns.expanded, example.id, false)
    assigns = assign(assigns, :is_expanded, is_expanded)

    ~H"""
    <div class="rounded-lg overflow-hidden" style="border: 1px solid rgba(155,126,200,0.08);">
      <button
        phx-click="toggle"
        phx-value-id={@example.id}
        class="w-full flex items-center gap-3 px-4 py-2.5 text-left transition-colors"
        style="background: var(--color-void);"
      >
        <.icon name="hero-chevron-right" class="w-4 h-4" style="color: var(--color-dust);" />
        <span class="text-sm font-ui" style="color: var(--color-lilac);">{@example.title}</span>
      </button>
      <%= if @is_expanded do %>
        <div
          class="px-4 py-3"
          style="background: var(--color-grimoire); border-top: 1px solid rgba(155,126,200,0.06);"
        >
          <pre
            phx-no-curly-interpolation
            class="text-xs font-mono p-3 rounded-lg overflow-x-auto"
            style="background: var(--color-void); color: var(--color-lavender);"
          ><code><%= @example.command %></code></pre>
        </div>
      <% end %>
    </div>
    """
  end

  defp method_badge_class("GET"),
    do: "text-xs font-mono font-bold px-2 py-0.5 rounded bg-emerald-500/20 text-emerald-400"

  defp method_badge_class("POST"),
    do: "text-xs font-mono font-bold px-2 py-0.5 rounded bg-amber-500/20 text-amber-400"

  defp method_badge_class("PATCH"),
    do: "text-xs font-mono font-bold px-2 py-0.5 rounded bg-amber-500/20 text-amber-400"

  defp method_badge_class("DELETE"),
    do: "text-xs font-mono font-bold px-2 py-0.5 rounded bg-red-500/20 text-red-400"

  defp method_badge_class(_),
    do: "text-xs font-mono font-bold px-2 py-0.5 rounded bg-gray-500/20 text-gray-400"

  defp response_status_class(status) do
    cond do
      String.starts_with?(status, "2") -> "bg-emerald-500/20 text-emerald-400"
      String.starts_with?(status, "4") -> "bg-red-500/20 text-red-400"
      String.starts_with?(status, "5") -> "bg-red-500/20 text-red-400"
      true -> "bg-gray-500/20 text-gray-400"
    end
  end

  defp origin do
    Application.get_env(:kiroku, KirokuWeb.Endpoint)[:url][:origin] || "https://your-domain.com"
  end
end
