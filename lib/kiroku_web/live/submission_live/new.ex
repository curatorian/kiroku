defmodule KirokuWeb.SubmissionLive.New do
  use KirokuWeb, :live_view

  alias Kiroku.{Repository, Content}
  alias Kiroku.Repository.Item
  alias Kiroku.Storage.Uploader
  alias Kiroku.Access.Authorization

  @item_types ~w(skripsi memorandum_hukum studi_kasus laporan_proyek karya_kreatif
    karya_teknologi jurnal_nasional jurnal_internasional prosiding capstone)

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    collections = list_all_collections()

    socket =
      socket
      |> assign(:item_types, @item_types)
      |> assign(:collections, collections)
      |> assign(:form, to_form(Item.changeset(%Item{}, %{}), as: :item))
      |> allow_upload(:cover,
        accept: ~w(.jpg .jpeg .png),
        max_entries: 1,
        max_file_size: 5_000_000
      )
      |> allow_upload(:abstract,
        accept: ~w(.pdf),
        max_entries: 1,
        max_file_size: 20_000_000
      )
      |> allow_upload(:fulltext,
        accept: ~w(.pdf),
        max_entries: 1,
        max_file_size: 100_000_000
      )
      |> allow_upload(:chapters,
        accept: ~w(.pdf),
        max_entries: 6,
        max_file_size: 50_000_000
      )
      |> allow_upload(:supplemental,
        accept: ~w(.pdf .docx .xlsx .csv .zip .pptx),
        max_entries: 10,
        max_file_size: 50_000_000
      )
      |> allow_upload(:media,
        accept: ~w(.mp3 .mp4 .mov .jpg .jpeg .png .tiff .zip),
        max_entries: 5,
        max_file_size: 500_000_000
      )
      |> allow_upload(:source,
        accept: ~w(.zip .tar .gz .ipynb .pdf),
        max_entries: 3,
        max_file_size: 200_000_000
      )
      |> allow_upload(:administrative,
        accept: ~w(.pdf),
        max_entries: 5,
        max_file_size: 20_000_000
      )

    if Authorization.can?(user, :create, %Item{}) do
      {:ok, socket}
    else
      {:ok, push_navigate(socket, to: ~p"/my/items")}
    end
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, assign(socket, :page_title, "Submit New Work")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_user}>
      <div class="max-w-3xl mx-auto px-4 py-8 space-y-8">
        <div>
          <.link
            navigate={~p"/my/items"}
            class="text-sm hover:text-white transition-colors"
            style="color: var(--color-lavender);"
          >
            ← Back to My Items
          </.link>
          <h1 class="font-heading text-3xl mt-2" style="color: var(--color-lilac);">
            Submit New Work
          </h1>
          <p class="text-sm mt-1" style="color: var(--color-quill);">
            Fill in the metadata and attach files. You can save as draft and return later.
          </p>
        </div>

        <.form
          for={@form}
          id="submission-form"
          phx-submit="save"
          phx-change="validate"
          class="space-y-6"
        >
          <%!-- Metadata section --%>
          <div id="metadata-section" class="kiroku-card p-6 space-y-5">
            <h2 class="font-heading text-lg" style="color: var(--color-wisteria);">Metadata</h2>

            <.input field={@form[:title]} type="text" label="Title" required />
            <.input field={@form[:title_alt]} type="text" label="Title (Alternate Language)" />

            <div>
              <label class="block text-sm font-medium mb-1.5" style="color: var(--color-wisteria);">
                Item Type
              </label>
              <select name="item[item_type]" id="item-type-select" class="kiroku-search-input w-full">
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
                Collection <span class="text-red-400">*</span>
              </label>
              <select
                name="item[collection_id]"
                id="collection-select"
                class="kiroku-search-input w-full"
                required
              >
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
            <.input
              field={@form[:abstract_alt]}
              type="textarea"
              label="Abstract (Alternate Language)"
            />
            <.input field={@form[:student_id]} type="text" label="Student ID (NIM/NPM)" />
            <.input field={@form[:student_name]} type="text" label="Student Name" />
            <.input field={@form[:faculty]} type="text" label="Faculty" />
            <.input field={@form[:department]} type="text" label="Department / Program Study" />
            <.input field={@form[:publication_year]} type="number" label="Publication Year" />
          </div>

          <%!-- File uploads section --%>
          <div id="files-section" class="kiroku-card p-6 space-y-6">
            <h2 class="font-heading text-lg" style="color: var(--color-wisteria);">Files</h2>

            <.upload_field
              upload={@uploads.cover}
              label="Cover Image"
              field_name="cover"
              hint="JPG/PNG, max 5 MB"
            />
            <.upload_field
              upload={@uploads.abstract}
              label="Abstract PDF"
              field_name="abstract"
              hint="PDF, max 20 MB"
            />
            <.upload_field
              upload={@uploads.fulltext}
              label="Full Text PDF"
              field_name="fulltext"
              hint="PDF, max 100 MB"
            />
            <.upload_field
              upload={@uploads.chapters}
              label="Chapters (up to 6)"
              field_name="chapters"
              hint="PDF per chapter, max 50 MB each"
            />
            <.upload_field
              upload={@uploads.supplemental}
              label="Supplemental Files"
              field_name="supplemental"
              hint="PDF, DOCX, XLSX, CSV, ZIP, PPTX — max 50 MB each"
            />
            <.upload_field
              upload={@uploads.media}
              label="Media Files"
              field_name="media"
              hint="MP3, MP4, MOV, images, ZIP — max 500 MB each"
            />
            <.upload_field
              upload={@uploads.source}
              label="Source Files"
              field_name="source"
              hint="ZIP, TAR, IPYNB, PDF — max 200 MB each"
            />
            <.upload_field
              upload={@uploads.administrative}
              label="Administrative Documents"
              field_name="administrative"
              hint="PDF, max 20 MB — visible only to staff"
            />
          </div>

          <div class="flex gap-3">
            <button
              type="submit"
              phx-value-submit_as="draft"
              class="px-5 py-2.5 rounded-lg font-semibold text-sm"
              style="background: rgba(155,126,200,0.2); color: var(--color-wisteria);"
            >
              Save Draft
            </button>
            <button
              type="submit"
              phx-value-submit_as="submitted"
              class="px-5 py-2.5 rounded-lg font-semibold text-sm"
              style="background: var(--color-patchouli); color: white;"
            >
              Submit for Review
            </button>
            <.link
              navigate={~p"/my/items"}
              class="px-5 py-2.5 rounded-lg font-medium text-sm"
              style="background: rgba(155,126,200,0.1); color: var(--color-quill);"
            >
              Cancel
            </.link>
          </div>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @doc false
  def upload_field(assigns) do
    ~H"""
    <div id={"upload-#{@field_name}"} class="space-y-2">
      <div class="flex items-baseline gap-2">
        <label class="text-sm font-medium" style="color: var(--color-wisteria);">{@label}</label>
        <span class="text-xs" style="color: var(--color-quill);">{@hint}</span>
      </div>
      <.live_file_input
        upload={@upload}
        class="block w-full text-sm file:mr-3 file:px-3 file:py-1.5 file:rounded-lg file:border-0 file:text-sm file:font-medium"
        style="color: var(--color-quill);"
      />
      <%= for entry <- @upload.entries do %>
        <div
          class="flex items-center gap-2 text-xs rounded-lg px-3 py-2"
          style="background: rgba(155,126,200,0.08); color: var(--color-wisteria);"
        >
          <.icon name="hero-document" class="w-4 h-4 shrink-0" />
          <span class="flex-1 truncate">{entry.client_name}</span>
          <span style="color: var(--color-quill);">
            {Float.round(entry.client_size / 1_000_000, 1)} MB
          </span>
          <button
            type="button"
            phx-click="cancel_upload"
            phx-value-ref={entry.ref}
            phx-value-field={@field_name}
            class="hover:opacity-70 transition-opacity"
          >
            <.icon name="hero-x-mark" class="w-4 h-4" />
          </button>
        </div>
        <div
          class="w-full h-1 rounded-full overflow-hidden"
          style="background: rgba(155,126,200,0.15);"
        >
          <div
            class="h-1 rounded-full transition-all"
            style={"width: #{entry.progress}%; background: var(--color-patchouli);"}
          >
          </div>
        </div>
        <%= for err <- upload_errors(@upload, entry) do %>
          <p class="text-xs" style="color: var(--color-ribbon-red);">
            {upload_error_to_string(err)}
          </p>
        <% end %>
      <% end %>
    </div>
    """
  end

  @impl true
  def handle_event("validate", %{"item" => params}, socket) do
    changeset =
      %Item{}
      |> Item.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: :item))}
  end

  @impl true
  def handle_event("cancel_upload", %{"ref" => ref, "field" => field}, socket) do
    field_atom = String.to_existing_atom(field)
    {:noreply, cancel_upload(socket, field_atom, ref)}
  end

  @impl true
  def handle_event("save", %{"item" => item_params} = params, socket) do
    user = socket.assigns.current_user
    submit_as = Map.get(params, "submit_as", "draft")
    status = if submit_as == "submitted", do: "submitted", else: "draft"

    attrs =
      item_params
      |> Map.put("submitter_id", user.id)
      |> Map.put("status", status)

    case Repository.create_item(attrs) do
      {:ok, item} ->
        socket = consume_and_create_bitstreams(socket, item)

        {:noreply,
         socket
         |> put_flash(
           :info,
           if(status == "submitted", do: "Submitted for review.", else: "Saved as draft.")
         )
         |> push_navigate(to: ~p"/my/items")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :item))}
    end
  end

  # ── Private ─────────────────────────────────────────────────────────────────

  defp consume_and_create_bitstreams(socket, item) do
    bucket = Kiroku.Settings.storage_bucket()

    upload_specs = [
      {:cover, :THUMBNAIL, 1, :open},
      {:abstract, :ORIGINAL, 1, :inherit},
      {:fulltext, :ORIGINAL, 2, :inherit},
      {:chapters, :CHAPTER, 1, :inherit},
      {:supplemental, :SUPPLEMENTAL, 1, :inherit},
      {:media, :MEDIA, 1, :inherit},
      {:source, :SOURCE, 1, :inherit},
      {:administrative, :ADMINISTRATIVE, 1, :restricted}
    ]

    Enum.each(upload_specs, fn {field, bundle, start_seq, _access} ->
      entries = socket.assigns.uploads[field].entries

      entries
      |> Enum.with_index(start_seq)
      |> Enum.each(fn {_entry, seq} ->
        consume_uploaded_entries(socket, field, fn %{path: tmp_path}, entry ->
          content = File.read!(tmp_path)
          key = Uploader.storage_key(item.id, bundle, entry.client_name)

          case Uploader.upload(key, content, mime_type: entry.client_type) do
            {:ok, _path} ->
              storage_type = Kiroku.Settings.storage_adapter()

              Content.create_bitstream(%{
                item_id: item.id,
                filename: entry.client_name,
                bundle_name: bundle,
                sequence: seq,
                description: bundle_description(bundle, seq),
                mime_type: entry.client_type,
                file_size: entry.client_size,
                storage_type: storage_type,
                storage_path: key,
                storage_bucket: bucket,
                access_level: :inherit
              })

            {:error, reason} ->
              require Logger
              Logger.error("Upload failed for #{entry.client_name}: #{inspect(reason)}")
          end

          :ok
        end)
      end)
    end)

    socket
  end

  defp bundle_description(:THUMBNAIL, _), do: "Cover image"
  defp bundle_description(:ORIGINAL, 1), do: "Abstract"
  defp bundle_description(:ORIGINAL, _), do: "Full text"
  defp bundle_description(:CHAPTER, seq), do: "Chapter #{seq}"
  defp bundle_description(:SUPPLEMENTAL, _), do: "Supplemental document"
  defp bundle_description(:MEDIA, _), do: "Media file"
  defp bundle_description(:SOURCE, _), do: "Source file"
  defp bundle_description(:ADMINISTRATIVE, _), do: "Administrative document"

  defp upload_error_to_string(:too_large), do: "File is too large"
  defp upload_error_to_string(:not_accepted), do: "File type not accepted"
  defp upload_error_to_string(:too_many_files), do: "Too many files"
  defp upload_error_to_string(err), do: "Upload error: #{inspect(err)}"

  defp list_all_collections do
    Repository.list_communities()
    |> Enum.flat_map(fn community ->
      Repository.list_collections_for_community(community.id)
    end)
  end
end
