defmodule KirokuWeb.SubmissionLive.Edit do
  use KirokuWeb, :live_view

  alias Kiroku.{Repository, Content}
  alias Kiroku.Repository.Item
  alias Kiroku.Storage.Uploader
  alias Kiroku.Access.Authorization

  @item_types ~w(skripsi memorandum_hukum studi_kasus laporan_proyek karya_kreatif
    karya_teknologi jurnal_nasional jurnal_internasional prosiding capstone)

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns.current_user
    item = Repository.get_item_with_preloads!(id)

    unless Authorization.can?(user, :update, item) do
      {:ok, push_navigate(socket, to: ~p"/my/items")}
    else
      collections = list_all_collections()

      socket =
        socket
        |> assign(:item, item)
        |> assign(:item_types, @item_types)
        |> assign(:collections, collections)
        |> assign(:page_title, "Edit — #{item.title}")
        |> assign(:form, to_form(Item.changeset(item, %{}), as: :item))
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

      {:ok, socket}
    end
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
            Edit Submission
          </h1>
          <p class="text-sm mt-1" style="color: var(--color-quill);">
            Update your submission metadata and files.
          </p>
        </div>

        <%!-- Existing bitstreams --%>
        <%= if @item.bitstreams != [] do %>
          <div id="existing-files" class="kiroku-card p-6 space-y-4">
            <h2 class="font-heading text-lg" style="color: var(--color-wisteria);">
              Existing Files
            </h2>
            <div class="space-y-2">
              <%= for bs <- Enum.filter(@item.bitstreams, &(&1.bundle_name == :ORIGINAL)) do %>
                <div
                  class="flex items-center gap-3 p-3 rounded-lg"
                  style="background: rgba(155,126,200,0.08);"
                >
                  <.icon
                    name="hero-document-text"
                    class="w-4 h-4 shrink-0 text-[var(--color-patchouli)]"
                  />
                  <div class="flex-1 min-w-0">
                    <p class="text-sm truncate" style="color: var(--color-wisteria);">
                      {bs.filename}
                    </p>
                    <p class="text-xs" style="color: var(--color-quill);">
                      {bs.description}
                      <%= if bs.file_size do %>
                        · {Float.round(bs.file_size / 1_048_576, 1)} MB
                      <% end %>
                    </p>
                  </div>
                  <button
                    type="button"
                    phx-click="delete_bitstream"
                    phx-value-id={bs.id}
                    class="text-xs px-2 py-1 rounded transition-colors hover:opacity-80"
                    style="background: rgba(255,80,80,0.15); color: #ff8080;"
                    data-confirm="Remove this file from the submission?"
                  >
                    Remove
                  </button>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>

        <.form
          for={@form}
          id="edit-submission-form"
          phx-submit="save"
          phx-change="validate"
          class="space-y-6"
        >
          <%!-- Metadata section --%>
          <div id="edit-metadata-section" class="kiroku-card p-6 space-y-5">
            <h2 class="font-heading text-lg" style="color: var(--color-wisteria);">Metadata</h2>

            <.input field={@form[:title]} type="text" label="Title" required />
            <.input field={@form[:title_alt]} type="text" label="Title (Alternate Language)" />

            <div>
              <label
                class="block text-sm font-medium mb-1.5"
                style="color: var(--color-wisteria);"
              >
                Item Type
              </label>
              <select
                name="item[item_type]"
                id="edit-item-type-select"
                class="kiroku-search-input w-full"
              >
                <option value="">Select type…</option>
                <%= for type <- @item_types do %>
                  <option value={type} selected={to_string(@form[:item_type].value) == type}>
                    {type |> String.replace("_", " ") |> String.capitalize()}
                  </option>
                <% end %>
              </select>
            </div>

            <div>
              <label
                class="block text-sm font-medium mb-1.5"
                style="color: var(--color-wisteria);"
              >
                Collection <span class="text-red-400">*</span>
              </label>
              <select
                name="item[collection_id]"
                id="edit-collection-select"
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

          <%!-- New file uploads section --%>
          <div id="edit-files-section" class="kiroku-card p-6 space-y-6">
            <h2 class="font-heading text-lg" style="color: var(--color-wisteria);">
              Add New Files
            </h2>
            <p class="text-xs -mt-2" style="color: var(--color-quill);">
              Uploading new files will add them alongside existing files.
            </p>

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

  @impl true
  def handle_event("validate", %{"item" => params}, socket) do
    changeset =
      socket.assigns.item
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
  def handle_event("delete_bitstream", %{"id" => bitstream_id}, socket) do
    case Content.get_bitstream(bitstream_id) do
      nil ->
        {:noreply, socket}

      bitstream ->
        Content.delete_bitstream(bitstream)
        item = Repository.get_item_with_preloads!(socket.assigns.item.id)
        {:noreply, assign(socket, :item, item)}
    end
  end

  @impl true
  def handle_event("save", %{"item" => item_params} = params, socket) do
    item = socket.assigns.item
    submit_as = Map.get(params, "submit_as", "draft")
    status = if submit_as == "submitted", do: "submitted", else: "draft"

    attrs = Map.put(item_params, "status", status)

    case Repository.update_item(item, attrs) do
      {:ok, updated_item} ->
        socket = consume_and_create_bitstreams(socket, updated_item)

        {:noreply,
         socket
         |> put_flash(
           :info,
           if(status == "submitted",
             do: "Resubmitted for review.",
             else: "Draft saved."
           )
         )
         |> push_navigate(to: ~p"/my/items")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :item))}
    end
  end

  # ── Reusable upload field component ─────────────────────────────────────────

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

  defp consume_and_create_bitstreams(socket, item) do
    bucket = Kiroku.Settings.storage_bucket()

    upload_specs = [
      {:cover, :THUMBNAIL, 1, :open},
      {:abstract, :ORIGINAL, 1, :inherit},
      {:fulltext, :ORIGINAL, 2, :inherit},
      {:chapters, :CHAPTER, 1, :inherit},
      {:supplemental, :SUPPLEMENTAL, 1, :inherit}
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
            {:ok, %{checksum: checksum}} ->
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
                checksum: checksum,
                checksum_algorithm: "MD5",
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

  defp upload_error_to_string(:too_large), do: "File is too large"
  defp upload_error_to_string(:not_accepted), do: "File type not accepted"
  defp upload_error_to_string(:too_many_files), do: "Too many files"
  defp upload_error_to_string(err), do: "Upload error: #{inspect(err)}"

  defp list_all_collections do
    Repository.list_active_collections()
  end
end
