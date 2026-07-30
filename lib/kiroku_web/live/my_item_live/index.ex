defmodule KirokuWeb.MyItemLive.Index do
  use KirokuWeb, :live_view

  import KirokuWeb.ItemForm
  import KirokuWeb.KirokuComponents

  alias Kiroku.{Content, Repository}
  alias Kiroku.Repository.Item
  alias Kiroku.Access.Authorization
  alias Kiroku.Storage.Uploader
  alias Kiroku.Pagination

  @item_types ~w(skripsi tesis disertasi tugas_akhir memorandum_hukum studi_kasus laporan_proyek karya_kreatif karya_teknologi jurnal_nasional jurnal_internasional prosiding capstone)

  # ── :index render ──────────────────────────────────────────────────────────

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

  # ── :new / :edit render ────────────────────────────────────────────────────

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

        <.form for={@form} id="item-form" phx-submit="save" phx-change="validate" class="space-y-6">
          <%!-- 1. Identity & type --%>
          <.identity_section form={@form} collections={@collections} />

          <%!-- 2. Abstract --%>
          <.abstract_section form={@form} />

          <%!-- 3. Contributor info — academic / thesis types only --%>
          <.contributor_section :if={academic_type?(@selected_type)} form={@form} />

          <%!-- 4. Type-specific detail fields --%>
          <.type_section type={@selected_type} form={@form} />

          <%!-- 5. Relations: authors, advisors, examiners, team, keywords --%>
          <.relations_section
            author_rows={@author_rows}
            advisor_rows={@advisor_rows}
            examiner_rows={@examiner_rows}
            team_rows={@team_rows}
            show_team={team_type?(@selected_type)}
            keywords={@keywords}
          />

          <%!-- 6. File uploads — fields shown follow the selected jenis karya --%>
          <.files_section uploads={@uploads} type={@selected_type} />

          <%!-- 7. Actions --%>
          <div class="kiroku-card p-5 flex flex-wrap items-center gap-3">
            <button
              type="submit"
              class="inline-flex items-center gap-2 px-5 py-2.5 rounded-lg font-semibold text-sm transition-all hover:brightness-110 active:scale-95"
              style="background: var(--color-patchouli); color: white; box-shadow: 0 2px 8px rgba(123,79,166,0.35);"
            >
              <.icon name="hero-arrow-down-tray" class="size-4" />
              {if @live_action == :new, do: "Submit Item", else: "Save Changes"}
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
    </Layouts.app>
    """
  end

  # ── Lifecycle ──────────────────────────────────────────────────────────────

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
     |> assign(:selected_type, "skripsi")
     |> assign(:form, nil)
     |> assign(:keywords, "")
     |> assign_relation_rows([])
     |> assign(:pagination, Pagination.build(0, 1, 20))
     |> allow_upload(:cover,
       accept: ~w(.jpg .jpeg .png),
       max_entries: 1,
       max_file_size: 5_000_000,
       auto_upload: true
     )
     |> allow_upload(:abstract,
       accept: ~w(.pdf),
       max_entries: 1,
       max_file_size: 20_000_000,
       auto_upload: true
     )
     |> allow_upload(:fulltext,
       accept: ~w(.pdf),
       max_entries: 1,
       max_file_size: 100_000_000,
       auto_upload: true
     )
     |> allow_upload(:chapters,
       accept: ~w(.pdf),
       max_entries: 6,
       max_file_size: 50_000_000,
       auto_upload: true
     )
     |> allow_upload(:supplemental,
       accept: ~w(.pdf .docx .xlsx .csv .zip .pptx),
       max_entries: 10,
       max_file_size: 50_000_000,
       auto_upload: true
     )
     |> allow_upload(:media,
       accept: ~w(.mp3 .mp4 .mov .jpg .jpeg .png .tiff .zip),
       max_entries: 5,
       max_file_size: 500_000_000,
       auto_upload: true
     )
     |> allow_upload(:source,
       accept: ~w(.zip .tar .gz .ipynb .pdf),
       max_entries: 3,
       max_file_size: 200_000_000,
       auto_upload: true
     )
     |> allow_upload(:administrative,
       accept: ~w(.pdf),
       max_entries: 5,
       max_file_size: 20_000_000,
       auto_upload: true
     )
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
      changeset = Item.changeset(%Item{}, %{item_type: :skripsi})

      socket
      |> assign(:page_title, "Submit New Item")
      |> assign(:current_item, nil)
      |> assign(:selected_type, "skripsi")
      |> assign(:keywords, "")
      |> assign_relation_rows([])
      |> assign(:form, to_form(changeset, as: :item))
      |> cancel_unused_uploads([])
    else
      socket
      |> put_flash(:error, "Item submission is currently disabled.")
      |> push_patch(to: ~p"/my/items")
    end
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    user = socket.assigns.current_user
    item = Repository.get_item_with_preloads!(id)

    if Authorization.can?(user, :update, item) do
      changeset = Item.changeset(item, %{})
      type = to_string(item.item_type)

      socket
      |> assign(:page_title, "Edit Item")
      |> assign(:current_item, item)
      |> assign(:selected_type, type)
      |> assign(:keywords, existing_to_keywords(item.item_keywords))
      |> assign(:author_rows, existing_to_rows(item.item_authors, :author))
      |> assign(:advisor_rows, existing_to_rows(item.item_advisors, :advisor))
      |> assign(:examiner_rows, existing_to_rows(item.item_examiners, :examiner))
      |> assign(:team_rows, existing_to_rows(item.item_team_members, :team))
      |> assign(:form, to_form(changeset, as: :item))
    else
      socket
      |> put_flash(:error, "Anda tidak memiliki akses untuk mengedit item ini.")
      |> push_patch(to: ~p"/my/items")
    end
  end

  # ── Events ─────────────────────────────────────────────────────────────────

  def handle_event("type_changed", %{"item" => %{"item_type" => type}}, socket) do
    keep = KirokuWeb.ItemForm.bundles_for_type(type)

    {:noreply, socket |> assign(:selected_type, type) |> cancel_unused_uploads(keep)}
  end

  def handle_event("validate", %{"item" => params} = all, socket) do
    item = socket.assigns.current_item || %Item{}

    changeset =
      item
      |> Item.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:selected_type, params["item_type"] || socket.assigns.selected_type)
     |> assign(:form, to_form(changeset, as: :item))
     |> assign(:keywords, Map.get(all, "keywords", ""))
     |> sync_rows(:author_rows, all, "authors", [:author_name, :affiliation, :email, :orcid])
     |> sync_rows(:advisor_rows, all, "advisors", [
       :advisor_name,
       :advisor_role,
       :nidn,
       :affiliation
     ])
     |> sync_rows(:examiner_rows, all, "examiners", [:examiner_name, :nidn, :affiliation])
     |> sync_rows(:team_rows, all, "team_members", [
       :member_name,
       :role,
       :student_id,
       :affiliation
     ])}
  end

  def handle_event("save", %{"item" => item_params} = params, socket) do
    user = socket.assigns.current_user

    case socket.assigns.live_action do
      :new ->
        attrs =
          item_params
          |> Map.put("submitter_id", user.id)
          |> Map.put("status", "submitted")

        case Repository.create_item(attrs) do
          {:ok, item} ->
            relations = %{
              authors: parse_relation_rows(params["authors"], "author_name"),
              advisors: parse_relation_rows(params["advisors"], "advisor_name"),
              examiners: parse_relation_rows(params["examiners"], "examiner_name"),
              team_members: parse_relation_rows(params["team_members"], "member_name"),
              keywords: parse_keywords(params["keywords"])
            }

            Repository.create_item_relations(item, relations)
            socket = consume_and_create_bitstreams(socket, item)

            {:noreply,
             socket
             |> put_flash(:info, "Item berhasil dikirim untuk review.")
             |> stream_insert(:items, item, at: 0)
             |> push_patch(to: ~p"/my/items")}

          {:error, changeset} ->
            {:noreply, assign(socket, :form, to_form(changeset, as: :item))}
        end

      :edit ->
        item = socket.assigns.current_item

        case Repository.update_item(item, item_params) do
          {:ok, updated_item} ->
            relations = %{
              authors: parse_relation_rows(params["authors"], "author_name"),
              advisors: parse_relation_rows(params["advisors"], "advisor_name"),
              examiners: parse_relation_rows(params["examiners"], "examiner_name"),
              team_members: parse_relation_rows(params["team_members"], "member_name"),
              keywords: parse_keywords(params["keywords"])
            }

            Repository.replace_item_relations(updated_item, relations)
            socket = consume_and_create_bitstreams(socket, updated_item)

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

  # ── Relation row add/remove events ──────────────────────────────────────────

  def handle_event("add_author", _, socket),
    do:
      {:noreply, assign(socket, :author_rows, socket.assigns.author_rows ++ [empty_row(:author)])}

  def handle_event("add_advisor", _, socket),
    do:
      {:noreply,
       assign(socket, :advisor_rows, socket.assigns.advisor_rows ++ [empty_row(:advisor)])}

  def handle_event("add_examiner", _, socket),
    do:
      {:noreply,
       assign(socket, :examiner_rows, socket.assigns.examiner_rows ++ [empty_row(:examiner)])}

  def handle_event("add_team", _, socket),
    do: {:noreply, assign(socket, :team_rows, socket.assigns.team_rows ++ [empty_row(:team)])}

  def handle_event("remove_author", %{"id" => id}, socket),
    do: {:noreply, assign(socket, :author_rows, remove_row(socket.assigns.author_rows, id))}

  def handle_event("remove_advisor", %{"id" => id}, socket),
    do: {:noreply, assign(socket, :advisor_rows, remove_row(socket.assigns.advisor_rows, id))}

  def handle_event("remove_examiner", %{"id" => id}, socket),
    do: {:noreply, assign(socket, :examiner_rows, remove_row(socket.assigns.examiner_rows, id))}

  def handle_event("remove_team", %{"id" => id}, socket),
    do: {:noreply, assign(socket, :team_rows, remove_row(socket.assigns.team_rows, id))}

  # ── Upload events ───────────────────────────────────────────────────────────

  def handle_event("cancel_upload", %{"ref" => ref, "field" => field}, socket) do
    field_atom = String.to_existing_atom(field)
    {:noreply, cancel_upload(socket, field_atom, ref)}
  end

  # ── Helpers ────────────────────────────────────────────────────────────────

  defp list_all_collections do
    Repository.list_active_collections()
  end

  defp staff?(%{user_type: type}) when type in [:admin, :superadmin], do: true
  defp staff?(_), do: false

  defp team_type?(type) when type in ~w(capstone laporan_proyek karya_teknologi), do: true
  defp team_type?(_), do: false

  defp parse_page(nil), do: 1

  defp parse_page(p) do
    case Integer.parse(p) do
      {n, ""} when n > 0 -> n
      _ -> 1
    end
  end

  # ── Relation row state helpers ──────────────────────────────────────────────

  defp assign_relation_rows(socket, rows) do
    socket
    |> assign(:author_rows, rows)
    |> assign(:advisor_rows, rows)
    |> assign(:examiner_rows, rows)
    |> assign(:team_rows, rows)
  end

  defp remove_row(rows, id),
    do: Enum.reject(rows, fn row -> to_string(row.id) == to_string(id) end)

  defp empty_row(:author) do
    %{id: row_id("a"), author_name: "", affiliation: "", email: "", orcid: ""}
  end

  defp empty_row(:advisor) do
    %{id: row_id("d"), advisor_name: "", advisor_role: "main_advisor", nidn: "", affiliation: ""}
  end

  defp empty_row(:examiner) do
    %{id: row_id("e"), examiner_name: "", nidn: "", affiliation: ""}
  end

  defp empty_row(:team) do
    %{id: row_id("t"), member_name: "", role: "", student_id: "", affiliation: ""}
  end

  defp row_id(prefix), do: "#{prefix}#{System.unique_integer([:positive])}"

  defp sync_rows(socket, assign_key, params, param_key, fields) do
    incoming = Map.get(params, param_key) || %{}

    updated =
      Enum.map(socket.assigns[assign_key], fn row ->
        inc = Map.get(incoming, to_string(row.id), %{})

        Enum.reduce(fields, row, fn field, acc ->
          Map.put(acc, field, Map.get(inc, Atom.to_string(field), Map.get(acc, field)))
        end)
      end)

    assign(socket, assign_key, updated)
  end

  defp parse_relation_rows(nil, _name_field), do: []

  defp parse_relation_rows(rows, name_field) when is_map(rows) do
    rows
    |> Map.values()
    |> Enum.reject(fn row -> blank?(Map.get(row, name_field)) end)
  end

  defp parse_relation_rows(rows, name_field) when is_list(rows) do
    Enum.reject(rows, fn row -> blank?(Map.get(row, name_field)) end)
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(s) when is_binary(s), do: String.trim(s) == ""
  defp blank?(_), do: false

  defp parse_keywords(nil), do: []

  defp parse_keywords(text) when is_binary(text) do
    text
    |> String.split(~r/[\n,]/, trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&%{keyword: &1})
  end

  defp existing_to_keywords(nil), do: ""

  defp existing_to_keywords(keywords) do
    Enum.map_join(keywords, ", ", & &1.keyword)
  end

  defp existing_to_rows(nil, _type), do: []

  defp existing_to_rows(records, :author) do
    Enum.map(records, fn a ->
      %{
        id: row_id("a"),
        author_name: a.author_name || "",
        affiliation: a.affiliation || "",
        email: a.email || "",
        orcid: a.orcid || ""
      }
    end)
  end

  defp existing_to_rows(records, :advisor) do
    Enum.map(records, fn a ->
      %{
        id: row_id("d"),
        advisor_name: a.advisor_name || "",
        advisor_role: a.advisor_role || "main_advisor",
        nidn: a.nidn || "",
        affiliation: a.affiliation || ""
      }
    end)
  end

  defp existing_to_rows(records, :examiner) do
    Enum.map(records, fn a ->
      %{
        id: row_id("e"),
        examiner_name: a.examiner_name || "",
        nidn: a.nidn || "",
        affiliation: a.affiliation || ""
      }
    end)
  end

  defp existing_to_rows(records, :team) do
    Enum.map(records, fn a ->
      %{
        id: row_id("t"),
        member_name: a.member_name || "",
        role: a.role || "",
        student_id: a.student_id || "",
        affiliation: a.affiliation || ""
      }
    end)
  end

  # ── Bitstream upload consumption ────────────────────────────────────────────

  defp cancel_unused_uploads(socket, keep) do
    unused =
      [:cover, :abstract, :fulltext, :chapters, :supplemental, :media, :source, :administrative] --
        keep

    Enum.reduce(unused, socket, fn field, acc ->
      Enum.reduce(acc.assigns.uploads[field].entries, acc, fn entry, inner ->
        cancel_upload(inner, field, entry.ref)
      end)
    end)
  end

  defp consume_and_create_bitstreams(socket, item) do
    bucket = Kiroku.Settings.storage_bucket()
    keep = KirokuWeb.ItemForm.bundles_for_type(to_string(item.item_type))

    upload_specs =
      [
        {:cover, :THUMBNAIL, 1},
        {:abstract, :ORIGINAL, 1},
        {:fulltext, :ORIGINAL, 2},
        {:chapters, :CHAPTER, 1},
        {:supplemental, :SUPPLEMENTAL, 1},
        {:media, :MEDIA, 1},
        {:source, :SOURCE, 1},
        {:administrative, :ADMINISTRATIVE, 1}
      ]
      |> Enum.filter(fn {field, _bundle, _seq} -> field in keep end)

    Enum.reduce(upload_specs, socket, fn {field, bundle, start_seq}, socket ->
      {done, in_progress} = uploaded_entries(socket, field)

      if done != [] and in_progress == [] do
        all_entries = socket.assigns.uploads[field].entries

        consume_uploaded_entries(socket, field, fn %{path: tmp_path}, entry ->
          seq_index = Enum.find_index(all_entries, &(&1.ref == entry.ref)) || 0
          seq = start_seq + seq_index

          content = File.read!(tmp_path)
          key = Uploader.storage_key(item.id, bundle, entry.client_name)

          result =
            case Uploader.upload(key, content, mime_type: entry.client_type) do
              {:ok, %{checksum: checksum}} ->
                Content.create_bitstream(%{
                  item_id: item.id,
                  filename: entry.client_name,
                  bundle_name: bundle,
                  sequence: seq,
                  description: bundle_description(bundle, seq),
                  mime_type: entry.client_type,
                  file_size: entry.client_size,
                  storage_type: Kiroku.Settings.storage_adapter(),
                  storage_path: key,
                  storage_bucket: bucket,
                  checksum: checksum,
                  checksum_algorithm: "MD5",
                  access_level: :inherit
                })

              {:error, reason} ->
                require Logger
                Logger.error("Upload failed for #{entry.client_name}: #{inspect(reason)}")
                {:error, reason}
            end

          {:ok, result}
        end)
      end

      socket
    end)
  end

  defp bundle_description(:THUMBNAIL, _), do: "Cover image"
  defp bundle_description(:ORIGINAL, 1), do: "Abstract"
  defp bundle_description(:ORIGINAL, _), do: "Full text"
  defp bundle_description(:CHAPTER, seq), do: "Bab #{seq}"
  defp bundle_description(:SUPPLEMENTAL, _), do: "Supplemental document"
  defp bundle_description(:MEDIA, _), do: "Media file"
  defp bundle_description(:SOURCE, _), do: "Source file"
  defp bundle_description(:ADMINISTRATIVE, _), do: "Administrative document"
end
