defmodule KirokuWeb.SubmissionLive.New do
  use KirokuWeb, :live_view

  import KirokuWeb.ItemForm

  alias Kiroku.{Repository, Content}
  alias Kiroku.Repository.Item
  alias Kiroku.Storage.Uploader
  alias Kiroku.Access.Authorization

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    collections = list_all_collections()

    socket =
      socket
      |> assign(:collections, collections)
      |> assign(:selected_type, "skripsi")
      |> assign(:form, to_form(Item.changeset(%Item{}, %{item_type: :skripsi}), as: :item))
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

    if Authorization.can?(user, :create, %Item{}) and submission_open?(user) do
      {:ok, socket}
    else
      {:ok,
       socket
       |> put_flash(:error, "Item submission is currently disabled.")
       |> push_navigate(to: ~p"/my/items")}
    end
  end

  defp submission_open?(%{user_type: type}) when type in [:admin, :superadmin], do: true

  defp submission_open?(_user), do: Kiroku.Settings.allow_user_submit?()

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, assign(socket, :page_title, "Submit New Work")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_user}>
      <div class="max-w-3xl mx-auto px-4 py-8 space-y-6">
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
          <%!-- 1. Identity & type --%>
          <.identity_section form={@form} collections={@collections} />

          <%!-- 2. Abstract --%>
          <.abstract_section form={@form} />

          <%!-- 3. Contributor info — academic / thesis types only --%>
          <.contributor_section :if={academic_type?(@selected_type)} form={@form} />

          <%!-- 4. Type-specific detail fields --%>
          <.type_section type={@selected_type} form={@form} />

          <%!-- File uploads section --%>
          <%!-- 5. Files --%>
          <div id="files-section" class="kiroku-card p-6 space-y-6">
            <div
              class="flex items-center gap-3 pb-4 mb-1 border-b"
              style="border-color: rgba(155,126,200,0.15);"
            >
              <div
                class="w-9 h-9 rounded-xl flex items-center justify-center shrink-0"
                style="background: color-mix(in srgb, var(--color-patchouli) 14%, transparent); color: var(--color-patchouli);"
              >
                <.icon name="hero-paper-clip" class="w-5 h-5" />
              </div>
              <div>
                <p
                  class="font-heading font-semibold text-base leading-tight"
                  style="color: var(--color-wisteria);"
                >
                  Berkas
                </p>
                <p class="text-xs leading-tight mt-0.5" style="color: var(--color-quill);">
                  Lampirkan berkas karya sesuai jenisnya
                </p>
              </div>
            </div>

            <.upload_field
              upload={@uploads.cover}
              label="Sampul / Cover"
              field_name="cover"
              hint="JPG/PNG, maks. 5 MB"
            />
            <.upload_field
              upload={@uploads.abstract}
              label="PDF Abstrak"
              field_name="abstract"
              hint="PDF, maks. 20 MB"
            />
            <.upload_field
              upload={@uploads.fulltext}
              label="Teks Lengkap (Full Text)"
              field_name="fulltext"
              hint="PDF, maks. 100 MB"
            />
            <.upload_field
              upload={@uploads.chapters}
              label="Per-Bab (maks. 6 berkas)"
              field_name="chapters"
              hint="PDF per bab, maks. 50 MB masing-masing"
            />
            <.upload_field
              upload={@uploads.supplemental}
              label="Berkas Suplemen"
              field_name="supplemental"
              hint="PDF, DOCX, XLSX, CSV, ZIP, PPTX — maks. 50 MB"
            />
            <.upload_field
              upload={@uploads.media}
              label="Berkas Media"
              field_name="media"
              hint="MP3, MP4, MOV, gambar, ZIP — maks. 500 MB"
            />
            <.upload_field
              upload={@uploads.source}
              label="Berkas Sumber"
              field_name="source"
              hint="ZIP, TAR, IPYNB, PDF — maks. 200 MB"
            />
            <.upload_field
              upload={@uploads.administrative}
              label="Dokumen Administratif"
              field_name="administrative"
              hint="PDF, maks. 20 MB — hanya terlihat oleh staf"
            />
          </div>

          <%!-- 6. Submit actions --%>
          <div class="kiroku-card p-5 flex flex-wrap items-center gap-3">
            <button
              type="submit"
              name="submit_as"
              value="submitted"
              class="inline-flex items-center gap-2 px-6 py-2.5 rounded-lg font-semibold text-sm transition-all hover:brightness-110 active:scale-95"
              style="background: var(--color-patchouli); color: white; box-shadow: 0 2px 8px rgba(123,79,166,0.35);"
            >
              <.icon name="hero-paper-airplane" class="size-4" /> Kirim untuk Direview
            </button>
            <button
              type="submit"
              name="submit_as"
              value="draft"
              class="inline-flex items-center gap-2 px-5 py-2.5 rounded-lg font-semibold text-sm transition-all hover:brightness-110 active:scale-95"
              style="background: color-mix(in srgb, var(--color-patchouli) 18%, transparent); color: var(--color-wisteria); border: 1px solid color-mix(in srgb, var(--color-patchouli) 30%, transparent);"
            >
              <.icon name="hero-bookmark" class="size-4" /> Simpan sebagai Draf
            </button>
            <.link
              navigate={~p"/my/items"}
              class="px-5 py-2.5 rounded-lg font-medium text-sm"
              style="color: var(--color-quill);"
            >
              Batal
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
  def handle_event("type_changed", %{"item" => %{"item_type" => type}}, socket) do
    {:noreply, assign(socket, :selected_type, type)}
  end

  @impl true
  def handle_event("validate", %{"item" => params}, socket) do
    changeset =
      %Item{}
      |> Item.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:selected_type, params["item_type"] || socket.assigns.selected_type)
     |> assign(:form, to_form(changeset, as: :item))}
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
