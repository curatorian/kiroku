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
          <p class="text-xs" style="color: var(--color-dust);">
            Token types (managed in <.link href={~p"/admin/api-tokens"} class="underline">API Tokens</.link>):
            <strong>user tokens</strong> inherit the account's access tier;
            <strong>device tokens</strong> are for kiosks — they report
            <code>tier: "kiosk"</code> on
            <code>GET /api/v1/kiosks/status</code> and must be approved by a superadmin.
            Until approved a device token reads <code>needs_reverify</code>; rotating or
            deleting it reads as <em>revoked</em> (401).
          </p>
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
            description:
              "List all active communities visible to the authenticated user. Flat list; every entry carries parent_community_id. Serves ETag + X-Total-Count (If-None-Match → 304).",
            params: [],
            response: %{status: "200 OK", body: communities_list_json()}
          })}
          {endpoint_card(assigns, %{
            id: "subcommunities-list",
            method: "GET",
            path: "/communities/:id/subcommunities",
            description:
              "List the direct children of a community (UUID or handle). X-Total-Count included.",
            params: [
              %{
                name: "id",
                type: "UUID | handle",
                required: true,
                description: "Parent community UUID or handle"
              }
            ],
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
          {endpoint_card(assigns, %{
            id: "communities-create",
            method: "POST",
            path: "/communities",
            description: "Create a new community. Requires superadmin privileges.",
            params: [],
            body: communities_create_body(),
            response: %{status: "201 Created", body: communities_create_json()}
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
          {endpoint_card(assigns, %{
            id: "collections-create",
            method: "POST",
            path: "/collections",
            description: "Create a new collection within a community. Requires admin privileges.",
            params: [],
            body: collections_create_body(),
            response: %{status: "201 Created", body: collections_create_json()}
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
            description:
              "Search and list published items. Returns X-Total-Count and a meta block {total_count, total_pages, page, per_page}. Search semantics: q is AND-of-tokens matches over title/abstract/metadata/extracted text plus author names and keywords (plainto_tsquery('indonesian')); default order is relevance with q, else published_at desc.",
            params: [
              %{
                name: "q",
                type: "string",
                required: false,
                description: "Full-text search across title, abstract, metadata, full text, authors, keywords"
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
                description: "Page number (default: 1, clamped to last page)"
              },
              %{
                name: "per_page",
                type: "integer",
                required: false,
                description: "Results per page (default: 20, max: 100)"
              },
              %{
                name: "sort",
                type: "string",
                required: false,
                description: "relevance (default) | published_at | title | author | subject"
              },
              %{
                name: "order",
                type: "string",
                required: false,
                description: "asc | desc (default desc for relevance/published_at, asc otherwise)"
              },
              %{
                name: "starts_with",
                type: "string",
                required: false,
                description:
                  "Alphabetical prefix browse on the current sort field (title default; author with sort=author; subject with sort=subject)"
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
            <.icon name="hero-arrow-down-tray" class="w-5 h-5" style="color: var(--color-patchouli);" />
            <h3 class="font-heading text-lg font-semibold" style="color: var(--color-lilac);">
              File Downloads
            </h3>
          </div>
          {endpoint_card(assigns, %{
            id: "bitstream-download",
            method: "GET",
            path: "/items/:item_id/bitstreams/:bitstream_id",
            description:
              "Download the file bytes. Supports random access via Range: 206 + Content-Range + Accept-Ranges + ETag; 416 on unsatisfiable ranges; item may be addressed by UUID or handle. Access is enforced per file — denied files get a 403 in the uniform error envelope.",
            params: [
              %{
                name: "item_id",
                type: "UUID | handle",
                required: true,
                description: "Item UUID or handle"
              },
              %{
                name: "bitstream_id",
                type: "UUID",
                required: true,
                description: "Bitstream UUID"
              }
            ],
            body:
              "Range (header, optional): bytes=a-b | bytes=a- | bytes=-suffix\ne.g. \"Range: bytes=0-\" for the first full read, \"Range: bytes=1048576-\" for random-access paging",
            response: %{status: "200 OK | 206 Partial Content", body: "binary file bytes"}
          })}
          {endpoint_card(assigns, %{
            id: "item-thumbnail",
            method: "GET",
            path: "/items/:item_id/thumbnails/:size",
            description:
              "Cover image bytes from the stored THUMBNAIL bitstream (size label is reserved for future variants). Prevents probing the file route for thumbnails.",
            params: [
              %{name: "item_id", type: "UUID | handle", required: true, description: "Item UUID or handle"},
              %{name: "size", type: "string", required: true, description: "small | medium | large (reserved)"}
            ],
            response: %{status: "200 OK", body: "image/jpeg bytes"}
          })}
        </div>

        <div class="kiroku-card p-6 space-y-4">
          <div class="flex items-center gap-2">
            <.icon name="hero-device-phone-mobile" class="w-5 h-5" style="color: var(--color-patchouli);" />
            <h3 class="font-heading text-lg font-semibold" style="color: var(--color-lilac);">
              Kiosk
            </h3>
          </div>
          {endpoint_card(assigns, %{
            id: "kiosk-status",
            method: "GET",
            path: "/kiosks/status",
            description:
              "Source of truth for kiosk device state. state: active (approved device token) | needs_reverify (device token not yet approved) | maintenance (admin flag on); a deleted/rotated token yields 401 = revoked. tier: kiosk for device tokens, public otherwise. Managed in Admin → Kiosk (/admin/kiosk).",
            params: [],
            response: %{status: "200 OK", body: kiosk_status_json()}
          })}
          {endpoint_card(assigns, %{
            id: "kiosk-events",
            method: "POST",
            path: "/events",
            description:
              "Visitor event ingestion for kiosks (SPEC 7.6). Accepts up to 500 events per request as {sessionId, type, timestamp, payload}[], idempotent per (sessionId, type, timestamp) — a replayed buffer is not double-counted.",
            params: [],
            body: events_body(),
            response: %{status: "202 Accepted", body: events_json()}
          })}
        </div>

        <div class="kiroku-card p-6 space-y-4">
          <div class="flex items-center gap-2">
            <.icon name="hero-exclamation-circle" class="w-5 h-5" style="color: var(--color-patchouli);" />
            <h3 class="font-heading text-lg font-semibold" style="color: var(--color-lilac);">
              Error Responses
            </h3>
          </div>
          <p class="text-sm" style="color: var(--color-wisteria);">
            Every non-2xx response under /api/v1 is application/json in a uniform envelope with a
            machine-parsable code. This includes framework-level 404s for unmatched routes.
          </p>
          <pre
            phx-no-curly-interpolation
            class="text-xs font-mono p-3 rounded-lg"
            style="background: var(--color-grimoire); color: var(--color-lavender);"
          ><code><%= error_envelope_example() %></code></pre>
          <p class="text-xs" style="color: var(--color-dust);">
            Codes: bad_request, unauthorized, forbidden, not_found, range_not_satisfiable,
            validation_error (422 adds a <code>fields</code> map of field-name → [messages],
            see example above), internal_error. If a /api/v1 path ever returns text/html
            (e.g. from a proxy level), report it — that is a misconfiguration, not the API.
          </p>
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
              id: "curl-create-community",
              title: "Create a community",
              command:
                "curl -X POST -H \"Authorization: Bearer kiroku_...\" -H \"Content-Type: application/json\" -d '{\"community\":{\"name\":\"Fakultas Teknik\",\"handle\":\"ft\",\"short_description\":\"Faculty of Engineering\"}}' /api/v1/communities"
            })}
            {curl_example(assigns, %{
              id: "curl-create-collection",
              title: "Create a collection",
              command:
                "curl -X POST -H \"Authorization: Bearer kiroku_...\" -H \"Content-Type: application/json\" -d '{\"collection\":{\"name\":\"Skripsi\",\"handle\":\"ft-skripsi\",\"community_id\":\"UUID\",\"short_description\":\"Undergraduate theses\"}}' /api/v1/collections"
            })}
            {curl_example(assigns, %{
              id: "curl-download-range",
              title: "Download a file with a Range request (kiosk reader)",
              command:
                "curl -i -H \"Authorization: Bearer kiroku_...\" -H \"Range: bytes=0-\" /api/v1/items/:item_id/bitstreams/:bitstream_id"
            })}
            {curl_example(assigns, %{
              id: "curl-file-upload",
              title: "Upload a file",
              command:
                "curl -X POST -H \"Authorization: Bearer kiroku_...\" -F \"file=@bab1.pdf\" -F \"bundle_name=CHAPTER\" /api/v1/items/:id/bitstreams"
            })}
            {curl_example(assigns, %{
              id: "curl-kiosk-status",
              title: "Kiosk status (device token)",
              command: "curl -H \"Authorization: Bearer kiroku_...\" /api/v1/kiosks/status"
            })}
            {curl_example(assigns, %{
              id: "curl-events",
              title: "Report visitor events batch",
              command:
                "curl -X POST -H \"Authorization: Bearer kiroku_...\" -H \"Content-Type: application/json\" -d '{\"events\":[{\"sessionId\":\"s1\",\"type\":\"page_view\",\"timestamp\":\"2026-10-27T09:01:23Z\",\"payload\":{\"item_id\":\"UUID\"}}]}' /api/v1/events"
            })}
            {curl_example(assigns, %{
              id: "curl-browse",
              title: "Alphabetical browse (sort + starts_with)",
              command:
                "curl -H \"Authorization: Bearer kiroku_...\" \"/api/v1/items?sort=title&order=asc&starts_with=A&per_page=20\""
            })}
            {curl_example(assigns, %{
              id: "curl-full-deposit-etag",
              title: "Communities with conditional GET (304 when unchanged)",
              command:
                "curl -i -H \"Authorization: Bearer kiroku_...\" -H \"If-None-Match: \\\"<etag>\\\"\" /api/v1/communities"
            })}
            {curl_example(assigns, %{
              id: "curl-full-deposit",
              title: "Full deposit — multipart (item + files)",
              command:
                "curl -X POST -H \"Authorization: Bearer kiroku_...\" -F \"item[title]=Judul Skripsi\" -F \"item[collection_id]=UUID\" -F \"item[item_type]=skripsi\" -F \"relations[authors][0][author_name]=Penulis\" -F \"files[fulltext]=@skripsi.pdf\" /api/v1/items/deposit"
            })}
            {curl_example(assigns, %{
              id: "curl-link-deposit",
              title: "Full deposit — link mode (item + URL files)",
              command:
                ~s(curl -X POST -H "Authorization: Bearer kiroku_..." -H "Content-Type: application/json" -d '{"deposit_type":"link","item":{"title":"Judul Skripsi","collection_id":"UUID","item_type":"skripsi"},"relations":{"authors":[{"author_name":"Penulis","sequence":1}],"keywords":["AI"]},"files":{"fulltext":["https://s3.example.com/paper.pdf"],"chapters":["https://s3.example.com/ch1.pdf"]},"storage_mode":"reference"}' /api/v1/items/deposit)
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
      ~s({"data":[{"id":"a1b2c3d4-...","name":"Fakultas Teknik","handle":"ft","parent_community_id":null,"short_description":"Faculty of Engineering","description":"...","position":1,"inserted_at":"2024-01-15T08:30:00Z"}]})

  defp communities_show_json,
    do:
      ~s({"data":{"id":"a1b2c3d4-...","name":"Fakultas Teknik","handle":"ft","short_description":"Faculty of Engineering","description":"...","position":1,"inserted_at":"2024-01-15T08:30:00Z","collections":[{"id":"e5f6g7h8-...","name":"Skripsi","handle":"ft-skripsi","short_description":"Undergraduate theses"}]}})

  defp collections_list_json,
    do:
      ~s({"data":[{"id":"e5f6g7h8-...","name":"Skripsi","handle":"ft-skripsi","short_description":"Undergraduate theses","community_id":"a1b2c3d4-...","position":1,"inserted_at":"2024-01-15T09:00:00Z"}]})

  defp collections_show_json,
    do:
      ~s({"data":{"id":"e5f6g7h8-...","name":"Skripsi","handle":"ft-skripsi","short_description":"Undergraduate theses","community_id":"a1b2c3d4-...","position":1,"inserted_at":"2024-01-15T09:00:00Z","item_count":142,"community":{"id":"a1b2c3d4-...","name":"Fakultas Teknik","handle":"ft"}}})

  defp communities_create_body do
    ~s({"community":{"name":"Fakultas Teknik","handle":"ft","short_description":"Faculty of Engineering","description":"Academic works from the Faculty of Engineering","position":1,"access_level":"open","parent_community_id":"optional-parent-uuid"}})
  end

  defp communities_create_json,
    do:
      ~s({"data":{"id":"new-uuid-...","name":"Fakultas Teknik","handle":"ft","short_description":"Faculty of Engineering","description":"...","position":1,"inserted_at":"2024-01-15T08:30:00Z"}})

  defp collections_create_body do
    ~s({"collection":{"name":"Skripsi","handle":"ft-skripsi","short_description":"Undergraduate theses","description":"Collection for undergraduate theses","community_id":"a1b2c3d4-...","position":1,"access_level":"open","default_item_access_level":"internal"}})
  end

  defp collections_create_json,
    do:
      ~s({"data":{"id":"new-uuid-...","name":"Skripsi","handle":"ft-skripsi","short_description":"Undergraduate theses","community_id":"a1b2c3d4-...","position":1,"inserted_at":"2024-01-15T09:00:00Z"}})

  defp items_list_json,
    do:
      ~s({"data":[{"id":"i1j2k3l4-...","handle":"12345","title":"Analisis Sentimen pada Ulasan Aplikasi Mobile","item_type":"skripsi","student_name":"Ahmad Rizki","department":"Teknik Informatika","faculty":"Fakultas Teknik","publication_year":2024,"published_at":"2024-06-15T10:00:00Z","language":"id","access_level":"open","collection":{"id":"e5f6g7h8-...","name":"Skripsi","handle":"ft-skripsi"}}],"meta":{"total_count":2487,"page":1,"per_page":20,"total_pages":125}})

  defp items_show_json do
    ~s({"data":{"id":"i1j2k3l4-...","handle":"12345","title":"Analisis Sentimen pada Ulasan Aplikasi Mobile","title_alt":"Sentiment Analysis on Mobile App Reviews","item_type":"skripsi","student_name":"Ahmad Rizki","student_id":"1234567890","department":"Teknik Informatika","faculty":"Fakultas Teknik","institution":"Universitas Indonesia","degree_level":"S1","abstract":"...","publication_year":2024,"date_issued":"2024-06-15","language":"id","access_level":"public","status":"published","published_at":"2024-06-15T10:00:00Z","collection":{"id":"e5f6g7h8-...","name":"Skripsi","handle":"ft-skripsi"},"authors":[{"id":"...","name":"Ahmad Rizki","name_alt":"A. Rizki","affiliation":"Universitas Indonesia","email":"ahmad@ui.ac.id","orcid":"0000-0001-2345-6789","sequence":1}],"advisors":[{"id":"...","name":"Dr. Budi Santoso","name_alt":"B. Santoso","role":"main_advisor","affiliation":"Universitas Indonesia","nidn":"0012345678","sequence":1}],"keywords":["sentiment analysis","mobile apps","NLP"],"metadata_extras":[]}})
  end

  defp bitstreams_list_json,
    do:
      ~s({"data":[{"id":"...","filename":"bab1.pdf","bundle_name":"CHAPTER","sequence":1,"description":"Bab 1 - Pendahuluan","mime_type":"application/pdf","file_size":245760,"access_level":"inherit"}]})

  defp kiosk_status_json,
    do:
      ~s({"state":"active","tier":"kiosk","server_time":"2026-10-27T09:00:00Z","announcement":null,"contact":"perpustakaan@example.ac.id","policies":{"allow_save":true,"allow_print":true,"allow_copy":false,"watermark":false,"idle_seconds":600,"reader_idle_seconds":900,"page_size_default":20}})

  defp events_body do
    """
    Content-Type: application/json

        events  (array, max 500) - each entry:
          sessionId  (string) - kiosk-generated session id (required)
          type       (string) - event type, max 100 chars (required)
          timestamp  (string) - ISO8601, timezone-aware, microsecond precision ok (required)
          payload    (object) - free-form JSON extra data

        Example entry:
        {"sessionId":"s1","type":"page_view","timestamp":"2026-10-27T09:01:23.500000Z","payload":{"item_id":"UUID"}}
    """
  end

  defp events_json, do: ~s({"accepted":12,"total":12})

  defp error_envelope_example,
    do:
      ~s(HTTP/1.1 404 Not Found
Content-Type: application/json; charset=utf-8

{"error":"not_found","message":"Not Found"}

// validation failure:
{"error":"validation_error","message":"Validation failed",
 "fields":{"title":["can't be blank"]}})

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
    ════════════════════════════════════════════════════════════════
    Mode 1: Multipart/form-data (file uploads)
    ════════════════════════════════════════════════════════════════
    Content-Type: multipart/form-data

    item[title]           (string)  - Item title (required)
    item[collection_id]   (UUID)    - Target collection (required)
    item[item_type]       (string)  - skripsi, tesis, disertasi, tugas-akhir,
                                      jurnal_nasional, jurnal_internasional, etc.
    item[abstract]        (string)  - Abstract / summary
    item[student_name]    (string)  - Student author name
    item[status]          (string)  - draft (default), submitted

    relations[authors]      (array)   - Author objects: author_name, sequence, affiliation, email, orcid
    relations[advisors]     (array)   - Advisor objects: advisor_name, advisor_role, affiliation, nidn
    relations[keywords]     (array)   - Keyword strings: ["keyword1", "keyword2"]

    files[cover]          (binary)  - Cover image (JPG/PNG, max 5 MB)
    files[fulltext]       (binary)  - Full text PDF (max 100 MB)
    files[chapters]       (binary)  - Chapter PDFs (multiple allowed, max 50 MB each)
    files[supplemental]   (binary)  - Supplemental documents
    files[media]          (binary)  - Media files (MP3, MP4, etc.)
    files[administrative] (binary)  - Administrative docs (staff-only)

    ════════════════════════════════════════════════════════════════
    Mode 2: JSON with link-based files
    ════════════════════════════════════════════════════════════════
    Content-Type: application/json

    {
      "deposit_type": "link",
      "item": {
        "title": "Judul Skripsi",
        "collection_id": "e5f6g7h8-...",
        "item_type": "skripsi",
        "abstract": "Abstrak...",
        "student_name": "Mahasiswa",
        "status": "draft"
      },
      "relations": {
        "authors": [{"author_name": "Penulis", "sequence": 1}],
        "advisors": [{"advisor_name": "Dr. X", "advisor_role": "main_advisor"}],
        "keywords": ["kata kunci"]
      },
      "files": {
        "fulltext": ["https://s3.example.com/paper.pdf"],
        "chapters": ["https://s3.example.com/ch1.pdf", "https://s3.example.com/ch2.pdf"],
        "cover": ["https://s3.example.com/cover.jpg"]
      },
      "storage_mode": "reference"
    }

    storage_mode options:
      "reference" — stores the URL as-is (no download)
      "download"  — downloads file and stores in local/S3 storage (default)
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
