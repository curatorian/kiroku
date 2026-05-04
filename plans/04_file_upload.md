# File Upload & Storage

## Kiroku — Bitstream Upload Pipeline

---

## 0. Overview

Every uploaded file becomes one row in the `bitstreams` table. Files are stored in S3 (or locally for dev).
The upload pipeline has two actors:

- **Browser → Server** via Phoenix LiveView's built-in upload (chunked, validated)
- **Server → S3** via a presigned PUT URL using `Req`
- **Browser → Bitstream URL** via a presigned GET URL (redirect, time-limited)

---

## 1. Add Dependencies to `mix.exs`

```elixir
# mix.exs — add to deps/0
{:ex_aws, "~> 2.5"},
{:ex_aws_s3, "~> 2.5"},
{:sweet_xml, "~> 0.7"},  # required by ex_aws XML parsing
```

`ex_aws` is used **only for presigned URL math** — it never makes HTTP calls itself.
All actual HTTP traffic uses `Req`.

---

## 2. Config

```elixir
# config/runtime.exs
config :ex_aws,
  access_key_id:     System.get_env("AWS_ACCESS_KEY_ID"),
  secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),
  region:            System.get_env("AWS_REGION", "ap-southeast-1")

config :kiroku, :storage,
  bucket:   System.get_env("S3_BUCKET", "kiroku-uploads"),
  region:   System.get_env("AWS_REGION", "ap-southeast-1"),
  # Set to :local for dev/test — files saved to priv/uploads/
  adapter:  String.to_existing_atom(System.get_env("STORAGE_ADAPTER", "s3"))
```

```elixir
# config/dev.exs
config :kiroku, :storage, adapter: :local
```

```elixir
# config/test.exs
config :kiroku, :storage, adapter: :local
```

---

## 3. `Storage.Uploader` Module

```elixir
# lib/kiroku/storage/uploader.ex
defmodule Kiroku.Storage.Uploader do
  @moduledoc """
  Handles file storage for bitstreams.
  Adapter is configured per env: :s3 | :local
  """

  @local_upload_dir "priv/uploads"

  # ── Upload ─────────────────────────────────────────────────────────────────

  @doc """
  Uploads binary content to storage. Returns {:ok, storage_path} | {:error, reason}.
  `key` is the full storage path/key, e.g. "items/abc123/fulltext.pdf"
  """
  def upload(key, content, opts \\ []) do
    mime_type = Keyword.get(opts, :mime_type, "application/octet-stream")

    case adapter() do
      :s3    -> upload_s3(key, content, mime_type)
      :local -> upload_local(key, content)
    end
  end

  # ── Presigned download URL (for serving files) ─────────────────────────────

  @doc """
  Returns a time-limited URL for downloading a file.
  For :local adapter returns the path directly (served by Plug.Static in dev).
  """
  def presign_url(bucket, key, opts \\ []) do
    expires_in = Keyword.get(opts, :expires_in, 3600)

    case adapter() do
      :s3 ->
        {:ok, url} = ExAws.S3.presigned_url(ex_aws_config(), :get, bucket, key,
          expires_in: expires_in
        )
        url

      :local ->
        "/uploads/#{key}"
    end
  end

  # ── Presigned upload URL (for direct browser-to-S3 upload, if needed) ──────

  @doc """
  Returns a presigned PUT URL so browsers can upload directly to S3.
  Only use for very large files (>50MB) — otherwise use the server-side path.
  """
  def presign_upload_url(bucket, key, opts \\ []) do
    expires_in = Keyword.get(opts, :expires_in, 900)
    {:ok, url} = ExAws.S3.presigned_url(ex_aws_config(), :put, bucket, key,
      expires_in: expires_in
    )
    url
  end

  # ── Delete ─────────────────────────────────────────────────────────────────

  def delete(bucket, key) do
    case adapter() do
      :s3 ->
        ExAws.S3.delete_object(bucket, key)
        |> ExAws.request(ex_aws_config())

      :local ->
        path = Path.join(@local_upload_dir, key)
        if File.exists?(path), do: File.rm!(path)
        :ok
    end
  end

  # ── Storage key generation ─────────────────────────────────────────────────

  @doc """
  Generates a storage key (S3 path) for a new bitstream.
  Format: "items/{item_id}/{bundle}/{uuid}-{filename}"
  """
  def storage_key(item_id, bundle_name, original_filename) do
    ext = Path.extname(original_filename)
    uuid = Ecto.UUID.generate()
    bundle_str = bundle_name |> to_string() |> String.downcase()
    "items/#{item_id}/#{bundle_str}/#{uuid}#{ext}"
  end

  # ── Private ────────────────────────────────────────────────────────────────

  defp upload_s3(key, content, mime_type) do
    bucket = bucket()

    request = ExAws.S3.put_object(bucket, key, content,
      content_type: mime_type,
      acl: :private
    )

    case ExAws.request(request, ex_aws_config()) do
      {:ok, _} -> {:ok, key}
      {:error, reason} -> {:error, reason}
    end
  end

  defp upload_local(key, content) do
    path = Path.join(@local_upload_dir, key)
    path |> Path.dirname() |> File.mkdir_p!()
    File.write!(path, content)
    {:ok, key}
  end

  defp adapter, do: Application.get_env(:kiroku, :storage)[:adapter] || :s3
  defp bucket,  do: Application.get_env(:kiroku, :storage)[:bucket]

  defp ex_aws_config do
    ExAws.Config.new(:s3,
      region: Application.get_env(:kiroku, :storage)[:region] ||
              Application.get_env(:ex_aws, :region)
    )
  end
end
```

---

## 4. Storage Key Convention

```
items/{item_id}/{bundle_lowercase}/{uuid}{ext}

Examples:
  items/6ba7b810-9dad-11d1-80b4-00c04fd430c8/thumbnail/a1b2c3d4.jpg
  items/6ba7b810.../original/e5f6g7h8.pdf
  items/6ba7b810.../chapter/i9j0k1l2.pdf
```

One `item_id` directory per item. Bundle subdirectories keep things organized.
Never expose storage keys directly in URLs — always route through `BitstreamController`.

---

## 5. Phoenix LiveView Upload Configuration

Configure uploads in `SubmissionLive.New` and `SubmissionLive.Edit`:

```elixir
# lib/kiroku_web/live/submission_live/new.ex

@impl true
def mount(_params, _session, socket) do
  socket =
    socket
    |> allow_upload(:cover,
        accept: ~w(.jpg .jpeg .png),
        max_entries: 1,
        max_file_size: 5_000_000,       # 5 MB
        auto_upload: false
    )
    |> allow_upload(:abstract,
        accept: ~w(.pdf),
        max_entries: 1,
        max_file_size: 20_000_000,      # 20 MB
        auto_upload: false
    )
    |> allow_upload(:fulltext,
        accept: ~w(.pdf),
        max_entries: 1,
        max_file_size: 100_000_000,     # 100 MB
        auto_upload: false
    )
    |> allow_upload(:chapters,
        accept: ~w(.pdf),
        max_entries: 6,                 # up to 6 chapters
        max_file_size: 50_000_000,      # 50 MB per chapter
        auto_upload: false
    )
    |> allow_upload(:supplemental,
        accept: ~w(.pdf .docx .xlsx .csv .zip .pptx),
        max_entries: 10,
        max_file_size: 50_000_000,
        auto_upload: false
    )
    |> allow_upload(:media,
        accept: ~w(.mp3 .mp4 .mov .jpg .jpeg .png .tiff .zip),
        max_entries: 5,
        max_file_size: 500_000_000,     # 500 MB for video
        auto_upload: false
    )
    |> allow_upload(:source,
        accept: ~w(.zip .tar.gz .ipynb .pdf),
        max_entries: 3,
        max_file_size: 200_000_000,
        auto_upload: false
    )
    |> allow_upload(:administrative,
        accept: ~w(.pdf),
        max_entries: 5,
        max_file_size: 20_000_000,
        auto_upload: false
    )

  {:ok, assign(socket, ...)}
end
```

---

## 6. Template Upload UI for Each Bundle

```heex
<%!-- Cover upload --%>
<div id="cover-upload" class="space-y-2">
  <label class="kiroku-label">Cover Image <span class="text-red-400">*</span></label>
  <.live_file_input upload={@uploads.cover} class="block w-full text-sm" />
  <%= for entry <- @uploads.cover.entries do %>
    <div class="flex items-center gap-2 text-xs" style="color: var(--color-wisteria);">
      <.icon name="hero-document" class="w-4 h-4" />
      {entry.client_name}
      <span>({Float.round(entry.client_size / 1_000_000, 1)} MB)</span>
      <button type="button" phx-click="cancel_upload" phx-value-ref={entry.ref} phx-value-field="cover">
        <.icon name="hero-x-mark" class="w-4 h-4" />
      </button>
    </div>
    <div class="w-full h-1 rounded" style="background: rgba(155,126,200,0.2);">
      <div class="h-1 rounded" style={"width: #{entry.progress}%; background: var(--color-patchouli);"}></div>
    </div>
    <%= for err <- upload_errors(@uploads.cover, entry) do %>
      <p class="text-xs" style="color: var(--color-ribbon-red);">{upload_error_to_string(err)}</p>
    <% end %>
  <% end %>
</div>
```

Add a helper in the LiveView:

```elixir
defp upload_error_to_string(:too_large),    do: "File is too large"
defp upload_error_to_string(:not_accepted), do: "File type not accepted"
defp upload_error_to_string(:too_many_files), do: "Too many files"
defp upload_error_to_string(err),           do: "Upload error: #{inspect(err)}"
```

---

## 7. Consuming Uploads and Creating Bitstreams

Call this after `Repository.create_item/1` succeeds, passing the new item's id:

```elixir
# lib/kiroku_web/live/submission_live/new.ex

defp consume_uploads_and_create_bitstreams(socket, item) do
  alias Kiroku.{Content, Storage}

  # Each upload field → {bundle_name, sequence_offset, access_level_override}
  upload_specs = [
    {:cover,          :THUMBNAIL,      1, :open},
    {:abstract,       :ORIGINAL,       1, :inherit},
    {:fulltext,       :ORIGINAL,       2, :inherit},
    {:chapters,       :CHAPTER,        1, :inherit},  # sequence increments per entry
    {:supplemental,   :SUPPLEMENTAL,   1, :inherit},
    {:media,          :MEDIA,          1, :inherit},
    {:source,         :SOURCE,         1, :inherit},
    {:administrative, :ADMINISTRATIVE, 1, :restricted},
  ]

  Enum.each(upload_specs, fn {field, bundle, start_seq, _access} ->
    entries = socket.assigns.uploads[field].entries

    entries
    |> Enum.with_index(start_seq)
    |> Enum.each(fn {_entry, seq} ->
      consume_uploaded_entries(socket, field, fn %{path: tmp_path}, entry ->
        content  = File.read!(tmp_path)
        key      = Storage.Uploader.storage_key(item.id, bundle, entry.client_name)
        bucket   = Application.get_env(:kiroku, :storage)[:bucket]

        {:ok, _path} = Storage.Uploader.upload(key, content, mime_type: entry.client_type)

        {:ok, _bitstream} = Content.create_bitstream(%{
          item_id:       item.id,
          filename:      entry.client_name,
          bundle_name:   bundle,
          sequence:      seq,
          description:   bundle_description(bundle, seq),
          mime_type:     entry.client_type,
          file_size:     entry.client_size,
          storage_type:  :s3,
          storage_path:  key,
          storage_bucket: bucket,
          access_level:  :inherit
          # Bitstream.changeset enforces :open for THUMBNAIL, :restricted for ADMINISTRATIVE
        })

        :ok
      end)
    end)
  end)

  socket
end

defp bundle_description(:THUMBNAIL, _),    do: "Cover image"
defp bundle_description(:ORIGINAL, 1),     do: "Abstract"
defp bundle_description(:ORIGINAL, _),     do: "Full text"
defp bundle_description(:CHAPTER, seq),    do: "Chapter #{seq}"
defp bundle_description(:SUPPLEMENTAL, _), do: "Supplemental document"
defp bundle_description(:MEDIA, _),        do: "Media file"
defp bundle_description(:SOURCE, _),       do: "Source file"
defp bundle_description(:ADMINISTRATIVE, _), do: "Administrative document"
```

### Cancelling uploads

```elixir
@impl true
def handle_event("cancel_upload", %{"ref" => ref, "field" => field}, socket) do
  field_atom = String.to_existing_atom(field)
  {:noreply, cancel_upload(socket, field_atom, ref)}
end
```

---

## 8. Full Submission Save Flow

```elixir
@impl true
def handle_event("submit", %{"item" => item_params}, socket) do
  user = socket.assigns.current_scope.user

  if Authorization.can?(user, :create_item, :any) do
    attrs =
      item_params
      |> Map.put("submitter_id", user.id)
      |> Map.put("status", "submitted")

    case Repository.create_item(attrs) do
      {:ok, item} ->
        socket = consume_uploads_and_create_bitstreams(socket, item)
        {:noreply, push_navigate(socket, to: ~p"/my/submissions")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: "item"))}
    end
  else
    {:noreply, put_flash(socket, :error, "Not authorized.")}
  end
end
```

---

## 9. `BitstreamController` — Serving Files

The existing controller serves files. For S3, generate a presigned GET URL and redirect:

```elixir
# lib/kiroku_web/controllers/bitstream_controller.ex

defp serve_bitstream(conn, %{storage_type: :s3} = bitstream) do
  url = Kiroku.Storage.Uploader.presign_url(
    bitstream.storage_bucket,
    bitstream.storage_path,
    expires_in: 3600
  )
  redirect(conn, external: url)
end

defp serve_bitstream(conn, %{storage_type: :local} = bitstream) do
  conn
  |> put_resp_content_type(bitstream.mime_type || "application/octet-stream")
  |> put_resp_header("content-disposition",
       ~s(attachment; filename="#{bitstream.filename}"))
  |> send_file(200, Path.join("priv/uploads", bitstream.storage_path))
end

defp serve_bitstream(conn, %{storage_type: :url, storage_url: url}) do
  redirect(conn, external: url)
end
```

---

## 10. Local Dev Setup

In dev, files are served from `priv/uploads/`. Add to `endpoint.ex`:

```elixir
# lib/kiroku_web/endpoint.ex
plug Plug.Static,
  at: "/uploads",
  from: {:kiroku, "priv/uploads"},
  only_matching: []
```

Create the directory:

```bash
mkdir -p priv/uploads
echo "priv/uploads/**" >> .gitignore
```

---

## 11. Migration — No Changes Needed

The `bitstreams` table already has `storage_bucket`, `storage_path`, `storage_url`, `storage_type`, `file_size`, `mime_type` columns from migration `20250101000006`. No new migration required for file upload support.

---

## 12. Testing File Uploads

In tests, use the `:local` adapter (configured in `config/test.exs`). Upload `Plug.Upload` structs via `Phoenix.LiveViewTest`:

```elixir
# test/kiroku_web/live/submission_live/new_test.exs

test "can submit with files", %{conn: conn} do
  user = insert(:user)
  conn = log_in_user(conn, user)
  {:ok, view, _html} = live(conn, ~p"/submit")

  # Simulate file upload
  cover_file = %Plug.Upload{
    path: "test/fixtures/cover.jpg",
    filename: "cover.jpg",
    content_type: "image/jpeg"
  }

  view
  |> file_input("#submission-form", :cover, [cover_file])
  |> render_upload("cover.jpg")

  # ... submit form ...
end
```

Store test fixture files in `test/fixtures/`.
