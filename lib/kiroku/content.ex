defmodule Kiroku.Content do
  @moduledoc """
  Context module for Bitstream (file attachments for repository items).
  Accessibility rules are enforced here so controllers and live views stay thin.
  """

  import Ecto.Query
  alias Kiroku.Repo
  alias Kiroku.Content.Bitstream
  alias Kiroku.Repository.Item

  def list_bitstreams_for_item(item_id) do
    Repo.all(
      from b in Bitstream,
        where: b.item_id == ^item_id,
        order_by: [b.bundle_name, b.sequence]
    )
  end

  def get_bitstream!(id), do: Repo.get!(Bitstream, id)

  def get_bitstream(id), do: Repo.get(Bitstream, id)

  def create_bitstream(attrs) do
    %Bitstream{}
    |> Bitstream.changeset(attrs)
    |> Repo.insert()
    |> maybe_enqueue_pdf_extraction()
    |> maybe_enqueue_thumbnail()
  end

  # After a successful insert, kick off async text extraction for PDFs in
  # content-bearing bundles. The worker skips non-PDFs internally, so this
  # is safe for every insert; gating on bundle/mime + storage_path avoids
  # no-op job rows for thumbnails, license uploads, and not-yet-staged
  # bitstreams (e.g. test fixtures).
  defp maybe_enqueue_pdf_extraction({:ok, %Bitstream{} = bs}) do
    if bs.bundle_name in [:ORIGINAL, :CHAPTER] and has_stored_bytes?(bs) do
      %{bitstream_id: bs.id}
      |> Kiroku.Workers.PdfTextWorker.new()
      |> Oban.insert()
    end

    {:ok, bs}
  end

  defp maybe_enqueue_pdf_extraction(other), do: other

  # Kick off thumbnail generation for ORIGINAL PDFs. The worker skips
  # internally if the item already has a THUMBNAIL, so it's safe to fire
  # for every ORIGINAL insert — including re-runs of the importer.
  defp maybe_enqueue_thumbnail({:ok, %Bitstream{} = bs}) do
    if bs.bundle_name == :ORIGINAL and has_stored_bytes?(bs) do
      %{bitstream_id: bs.id}
      |> Kiroku.Workers.ThumbnailWorker.new()
      |> Oban.insert()
    end

    {:ok, bs}
  end

  defp maybe_enqueue_thumbnail(other), do: other

  defp has_stored_bytes?(%Bitstream{storage_type: type, storage_path: path})
       when type in [:local, :s3] and is_binary(path) and path != "",
       do: true

  defp has_stored_bytes?(_), do: false

  def update_bitstream(%Bitstream{} = bitstream, attrs) do
    bitstream
    |> Bitstream.changeset(attrs)
    |> Repo.update()
  end

  def delete_bitstream(%Bitstream{} = bitstream), do: Repo.delete(bitstream)

  @doc """
  Determines whether `user` may access `bitstream` belonging to `item`.

  Rules (evaluated in order):
  1. THUMBNAIL bundles → always accessible.
  2. ADMINISTRATIVE / LICENSE bundles → reviewer, admin, superadmin only.
  3. ORIGINAL sequence == 1 (abstract PDF) → never embargoed, but still
     subject to the bitstream's own access_level.
  4. Locked bitstreams under `:closed` mode → **superadmin only**.
     Evaluated before the staff bypass so reviewer/admin are also blocked.
  5. Staff (reviewer/admin/superadmin) → always accessible (bypass embargo).
  6. Locked bitstreams under `:internal` mode → require :internal role
     (or any higher staff role, already handled above).
  7. If the item's files are embargoed → not accessible.
  8. Otherwise → evaluate the bitstream's own access_level:
       :open       → accessible to everyone
       :internal   → accessible to any logged-in user
       :inherit    → use the parent item's access_level
       :restricted → staff only
       :closed     → no one (except staff, already handled above)
  """
  def accessible?(%Bitstream{bundle_name: :THUMBNAIL}, _user, _item), do: true

  def accessible?(%Bitstream{bundle_name: bundle}, user, _item)
      when bundle in [:ADMINISTRATIVE, :LICENSE] do
    user_is_staff?(user)
  end

  def accessible?(%Bitstream{} = bitstream, user, %Item{} = item) do
    cond do
      bitstream_locked?(bitstream) and Kiroku.Settings.file_lock_mode() == :closed ->
        user_is_superadmin?(user)

      user_is_staff?(user) ->
        true

      bitstream_locked?(bitstream) and not user_is_internal?(user) ->
        false

      Item.files_embargoed?(item) and not abstract?(bitstream) ->
        false

      true ->
        access_level_allows?(bitstream.access_level, item.access_level, user)
    end
  end

  @doc """
  Returns true if the bitstream's description matches a globally locked
  pattern (configured in admin settings).
  """
  def bitstream_locked?(%Bitstream{description: description}) when is_binary(description) do
    description in Kiroku.Settings.locked_bitstream_descriptions()
  end

  def bitstream_locked?(_), do: false

  # ORIGINAL bundle, sequence 1 is the abstract PDF — exempt from embargo.
  defp abstract?(%Bitstream{bundle_name: :ORIGINAL, sequence: 1}), do: true
  defp abstract?(%Bitstream{}), do: false

  defp access_level_allows?(:open, _item_level, _user), do: true

  # :internal = any authenticated user (logged-in). Anonymous (nil) is denied;
  # any non-nil user — including submitters — is granted.
  defp access_level_allows?(:internal, _item_level, nil), do: false
  defp access_level_allows?(:internal, _item_level, _user), do: true

  defp access_level_allows?(:inherit, item_level, user),
    do: access_level_allows?(item_level, item_level, user)

  defp access_level_allows?(:restricted, _item_level, user), do: user_is_staff?(user)

  defp access_level_allows?(:closed, _item_level, _user), do: false

  defp user_is_staff?(%{user_type: type}), do: type in [:reviewer, :admin, :superadmin]
  defp user_is_staff?(_), do: false

  defp user_is_internal?(%{user_type: :internal}), do: true
  defp user_is_internal?(_), do: false

  defp user_is_superadmin?(%{user_type: :superadmin}), do: true
  defp user_is_superadmin?(_), do: false

  # ── Fixity (checksum verification) ─────────────────────────────────────────
  #
  # Bitstreams store an MD5 checksum at upload time. A periodic Oban job
  # (FixityWorker) recomputes the checksum from the stored bytes and compares
  # it to the stored value, recording each result in bitstream_fixity_checks.

  alias Kiroku.Content.BitstreamFixityCheck
  alias Kiroku.Content.BitstreamExtractedText
  alias Kiroku.Storage.Uploader

  @fixity_batch_size 50
  @fixity_recheck_after_days 30

  @doc """
  Verifies a single bitstream's checksum against its stored bytes.

    * If the bytes are readable and a stored checksum exists → verify, record,
      and update `last_fixity_at`/`last_fixity_ok`.
    * If the bytes are readable but no checksum is stored yet → record a
      baseline (establishes the checksum for the first time, e.g. for legacy
      bitstreams uploaded before checksum-on-upload existed).
    * If the bytes can't be read → record a check with `ok: nil` and the error.

  Returns `{:ok, boolean | nil}` (the check outcome) | `{:error, reason}`.
  """
  def check_bitstream(%Bitstream{} = bitstream) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case Uploader.read_bytes(bitstream) do
      {:ok, bytes} ->
        actual = Uploader.checksum(bytes)

        {expected, ok, changes} =
          case bitstream.checksum do
            nil ->
              # No baseline yet — establish it.
              {actual, true, %{checksum: actual, checksum_algorithm: "MD5"}}

            stored ->
              {stored, stored == actual, %{}}
          end

        {:ok, _} =
          %BitstreamFixityCheck{}
          |> BitstreamFixityCheck.changeset(%{
            bitstream_id: bitstream.id,
            expected_checksum: expected,
            actual_checksum: actual,
            ok: ok
          })
          |> Repo.insert()

        {:ok, _} =
          bitstream
          |> Ecto.Changeset.cast(
            Map.merge(changes, %{last_fixity_at: now, last_fixity_ok: ok}),
            [:checksum, :checksum_algorithm, :last_fixity_at, :last_fixity_ok]
          )
          |> Repo.update()

        {:ok, ok}

      {:error, reason} ->
        {:ok, _} =
          %BitstreamFixityCheck{}
          |> BitstreamFixityCheck.changeset(%{
            bitstream_id: bitstream.id,
            expected_checksum: bitstream.checksum || "",
            ok: nil,
            error: inspect(reason)
          })
          |> Repo.insert()

        {:ok, _} =
          bitstream
          |> Ecto.Changeset.cast(
            %{last_fixity_at: now, last_fixity_ok: nil},
            [:last_fixity_at, :last_fixity_ok]
          )
          |> Repo.update()

        {:error, reason}
    end
  end

  def check_bitstream(id) when is_binary(id) do
    case get_bitstream(id) do
      %Bitstream{} = bs -> check_bitstream(bs)
      nil -> {:error, :not_found}
    end
  end

  @doc """
  Runs fixity checks for a batch of bitstreams that are due (never checked, or
  last checked more than `@fixity_recheck_after_days` days ago). Skips
  `:url`-hosted bitstreams (not verifiable).

  Returns a map of counts: `%{checked: n, ok: n, failed: n, errored: n}`.
  """
  def run_fixity_batch(opts \\ []) do
    limit = Keyword.get(opts, :limit, @fixity_batch_size)
    cutoff = DateTime.utc_now() |> DateTime.add(-@fixity_recheck_after_days * 86_400, :second)

    bitstreams =
      Repo.all(
        from b in Bitstream,
          where:
            b.storage_type in [:local, :s3] and
              (is_nil(b.last_fixity_at) or b.last_fixity_at < ^cutoff),
          order_by: [asc_nulls_first: b.last_fixity_at],
          limit: ^limit
      )

    Enum.reduce(bitstreams, %{checked: 0, ok: 0, failed: 0, errored: 0}, fn bs, acc ->
      case check_bitstream(bs) do
        {:ok, true} -> %{acc | checked: acc.checked + 1, ok: acc.ok + 1}
        {:ok, false} -> %{acc | checked: acc.checked + 1, failed: acc.failed + 1}
        {:ok, nil} -> %{acc | checked: acc.checked + 1, errored: acc.errored + 1}
        {:error, _} -> %{acc | checked: acc.checked + 1, errored: acc.errored + 1}
      end
    end)
  end

  @doc """
  Aggregate fixity status across all verifiable bitstreams, for the admin
  dashboard: counts of verified-ok, verified-failed, never-checked, and
  externally-hosted (unverifiable).
  """
  def fixity_summary do
    base = from b in Bitstream, where: b.storage_type in [:local, :s3]

    %{
      ok: Repo.aggregate(where(base, [b], b.last_fixity_ok == true), :count, :id),
      failed: Repo.aggregate(where(base, [b], b.last_fixity_ok == false), :count, :id),
      unchecked: Repo.aggregate(where(base, [b], is_nil(b.last_fixity_at)), :count, :id),
      unverifiable:
        Repo.aggregate(from(b in Bitstream, where: b.storage_type == :url), :count, :id)
    }
  end

  @doc "Recent fixity-check failures (for an admin report)."
  def list_fixity_failures(limit \\ 20) do
    Repo.all(
      from c in BitstreamFixityCheck,
        where: c.ok == false,
        order_by: [desc: c.inserted_at],
        limit: ^limit,
        preload: [:bitstream]
    )
  end

  # ── PDF text extraction ─────────────────────────────────────────────────────
  #
  # Shells out to `pdftotext` (poppler-utils) to pull the text content of an
  # ORIGINAL-bundle PDF. The result is persisted to bitstream_extracted_text
  # and aggregated into the parent item's denormalized `extracted_text`
  # column, which the PostgreSQL `search_vector` generated column folds into
  # the GIN-indexed tsvector used by full-text search.

  @extractor "pdftotext"

  @doc """
  Extracts text from `bitstream` (a PDF) via `pdftotext`.

  Skips non-PDFs and externally-hosted bitstreams (cannot read bytes).
  Persists the result and rebuilds the parent item's `extracted_text` cache
  so the search index stays fresh.

  Returns:
    * `{:ok, text}`         — extraction succeeded (text may be empty)
    * `{:ok, nil}`          — skipped (non-PDF or :url storage)
    * `{:error, reason}`    — extraction failed (bytes unreadable, pdftotext
                              missing/errored); see the persisted row's
                              `:error` field for details
  """
  def extract_text(%Bitstream{} = bitstream) do
    cond do
      not pdf?(bitstream) ->
        {:ok, nil}

      bitstream.storage_type == :url ->
        {:ok, nil}

      true ->
        extract_pdf(bitstream)
    end
  end

  def extract_text(id) when is_binary(id) do
    case get_bitstream(id) do
      %Bitstream{} = bs -> extract_text(bs)
      nil -> {:error, :not_found}
    end
  end

  defp extract_pdf(%Bitstream{} = bitstream) do
    now = DateTime.utc_now()

    case Uploader.read_bytes(bitstream) do
      {:ok, bytes} ->
        case run_pdftotext(bytes) do
          {:ok, text, page_count} ->
            persist_extraction(bitstream, %{
              text: text,
              page_count: page_count,
              extractor: @extractor,
              error: nil,
              extracted_at: now
            })

            recompute_item_extracted_text(bitstream.item_id)
            {:ok, text}

          {:error, reason} ->
            persist_extraction(bitstream, %{
              text: nil,
              page_count: nil,
              extractor: @extractor,
              error: extractor_error_string(reason),
              extracted_at: now
            })

            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp run_pdftotext(bytes) do
    if System.find_executable("pdftotext") == nil do
      {:error, :pdftotext_not_found}
    else
      # System.cmd/3 in Elixir 1.20+ no longer accepts :input, so we write
      # the bytes to a temp file and have pdftotext read it directly.
      tmp_in =
        Path.join(
          System.tmp_dir!(),
          "kiroku-pdf-#{System.unique_integer([:positive, :monotonic])}.pdf"
        )

      try do
        File.write!(tmp_in, bytes)

        case System.cmd("pdftotext", [tmp_in, "-"], stderr_to_stdout: true) do
          {text, 0} ->
            {:ok, text, count_pages(bytes)}

          {output, exit_code} ->
            {:error, {:extractor_failed, exit_code, output}}
        end
      after
        File.rm(tmp_in)
      end
    end
  end

  # Best-effort page count via pdfinfo (also from poppler-utils). Returns nil
  # if pdfinfo is unavailable or fails — we don't want to fail the whole
  # extraction just because page counting broke.
  defp count_pages(bytes) do
    if System.find_executable("pdfinfo") == nil do
      nil
    else
      tmp_in =
        Path.join(
          System.tmp_dir!(),
          "kiroku-pdf-info-#{System.unique_integer([:positive, :monotonic])}.pdf"
        )

      try do
        File.write!(tmp_in, bytes)

        case System.cmd("pdfinfo", [tmp_in], stderr_to_stdout: true) do
          {info, 0} ->
            case Regex.run(~r/^Pages:\s+(\d+)/m, info) do
              [_, n] -> String.to_integer(n)
              _ -> nil
            end

          _ ->
            nil
        end
      after
        File.rm(tmp_in)
      end
    end
  end

  defp extractor_error_string(:pdftotext_not_found), do: "pdftotext binary not on PATH"

  defp extractor_error_string({:extractor_failed, code, output}),
    do: "pdftotext exited #{code}: #{output}"

  defp extractor_error_string(other), do: inspect(other)

  # A bitstream is considered a PDF if its mime_type advertises PDF or its
  # filename ends with .pdf. We accept a few common mime variants seen in the
  # wild.
  defp pdf?(%Bitstream{mime_type: mime}) when mime in ~w(application/pdf application/x-pdf),
    do: true

  defp pdf?(%Bitstream{filename: name}) when is_binary(name),
    do: String.ends_with?(String.downcase(name), ".pdf")

  defp pdf?(_), do: false

  # Persists (upserts) the extraction result for a single bitstream.
  defp persist_extraction(bitstream, attrs) do
    {:ok, _} =
      %BitstreamExtractedText{}
      |> BitstreamExtractedText.changeset(Map.put(attrs, :bitstream_id, bitstream.id))
      |> Repo.insert(
        on_conflict: :replace_all,
        conflict_target: :bitstream_id
      )

    :ok
  end

  @doc """
  Recomputes `items.extracted_text` by concatenating the text of all
  successfully extracted bitstreams for `item_id`, in bundle/sequence order.

  The PostgreSQL `search_vector` column is GENERATED from title + abstract +
  extracted_text, so updating this column automatically refreshes the
  GIN-indexed full-text search index.
  """
  def recompute_item_extracted_text(item_id) when is_binary(item_id) do
    rows =
      Repo.all(
        from e in BitstreamExtractedText,
          join: b in assoc(e, :bitstream),
          where: e.text != "" and not is_nil(e.text) and b.item_id == ^item_id,
          order_by: [b.bundle_name, b.sequence],
          select: e.text
      )

    concatenated = Enum.join(rows, " \n")

    {:ok, _} =
      Kiroku.Repository.Item
      |> Repo.get(item_id)
      |> case do
        nil -> {:ok, nil}
        item -> item |> Ecto.Changeset.change(%{extracted_text: concatenated}) |> Repo.update()
      end

    :ok
  end

  # ── Thumbnail generation ────────────────────────────────────────────────────
  #
  # Renders the first page of an ORIGINAL-bundle PDF as a JPEG via `pdftoppm`
  # (poppler-utils, same package as pdftotext). Stores the result as a
  # THUMBNAIL bitstream on the same item. Skips silently when:
  #   * the source bitstream is not a PDF
  #   * the item already has a THUMBNAIL bitstream (user cover / legacy import)
  #   * pdftoppm is not installed
  #   * the source bytes can't be read (:url storage, etc.)

  @thumbnail_width 400
  @thumbnail_mime "image/jpeg"

  @doc """
  Generates a first-page thumbnail from `bitstream` (a PDF) and stores it as
  a THUMBNAIL bitstream on the same item.

  Returns:
    * `{:ok, bitstream}`       — thumbnail generated and stored
    * `{:ok, :skipped}`        — source is not a PDF, or item already has a thumb
    * `{:ok, :no_pdftoppm}`    — pdftoppm binary not on PATH
    * `{:error, reason}`       — generation or storage failed
  """
  def generate_thumbnail(%Bitstream{} = bitstream) do
    cond do
      not pdf?(bitstream) ->
        {:ok, :skipped}

      bitstream.storage_type == :url ->
        {:ok, :skipped}

      item_has_thumbnail?(bitstream.item_id) ->
        {:ok, :skipped}

      System.find_executable("pdftoppm") == nil ->
        {:ok, :no_pdftoppm}

      true ->
        generate_pdf_thumbnail(bitstream)
    end
  end

  def generate_thumbnail(id) when is_binary(id) do
    case get_bitstream(id) do
      %Bitstream{} = bs -> generate_thumbnail(bs)
      nil -> {:error, :not_found}
    end
  end

  defp generate_pdf_thumbnail(%Bitstream{} = bitstream) do
    case Uploader.read_bytes(bitstream) do
      {:ok, bytes} ->
        case render_pdf_first_page(bytes) do
          {:ok, thumb_bytes} ->
            store_thumbnail(bitstream, thumb_bytes)

          {:error, reason} ->
            require Logger

            Logger.warning(
              "Thumbnail generation failed bitstream=#{bitstream.id}: #{inspect(reason)}"
            )

            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Renders page 1 of the PDF as a JPEG no wider than @thumbnail_width px.
  # Uses a temp file for input (Elixir 1.20 dropped System.cmd's :input).
  defp render_pdf_first_page(bytes) do
    tmp_prefix =
      Path.join(
        System.tmp_dir!(),
        "kiroku-thumb-#{System.unique_integer([:positive, :monotonic])}"
      )

    tmp_pdf = tmp_prefix <> ".pdf"
    tmp_out = tmp_prefix

    try do
      File.write!(tmp_pdf, bytes)

      case System.cmd("pdftoppm", [
             "-jpeg",
             "-f",
             "1",
             "-l",
             "1",
             "-singlefile",
             "-scale-to",
             to_string(@thumbnail_width),
             tmp_pdf,
             tmp_out
           ]) do
        {_output, 0} ->
          # pdftoppm appends .jpg to the output prefix with -singlefile.
          thumb_path = tmp_out <> ".jpg"

          if File.exists?(thumb_path) do
            {:ok, File.read!(thumb_path)}
          else
            {:error, :no_output_file}
          end

        {output, exit_code} ->
          {:error, {:pdftoppm_failed, exit_code, output}}
      end
    after
      File.rm(tmp_pdf)
      File.rm(tmp_out <> ".jpg")
    end
  end

  # Stores the thumbnail bytes and creates a THUMBNAIL bitstream row.
  defp store_thumbnail(%Bitstream{} = source, thumb_bytes) do
    # Mirror the source bitstream's storage adapter so the thumbnail lives
    # alongside the original file.
    key = Uploader.storage_key(source.item_id, "THUMBNAIL", "thumb.jpg")

    case Uploader.upload(key, thumb_bytes, mime_type: @thumbnail_mime) do
      {:ok, %{path: path, checksum: checksum, size: size}} ->
        attrs =
          Map.merge(Uploader.record_attrs(), %{
            item_id: source.item_id,
            filename: "thumb.jpg",
            bundle_name: :THUMBNAIL,
            sequence: 1,
            description: "Auto-generated cover",
            mime_type: @thumbnail_mime,
            file_size: size,
            checksum: checksum,
            checksum_algorithm: "MD5",
            storage_path: path,
            access_level: :open
          })

        # Delete any stale THUMBNAIL row first (shouldn't exist, but be safe).
        Repo.delete_all(
          from b in Bitstream,
            where: b.item_id == ^source.item_id and b.bundle_name == :THUMBNAIL
        )

        case create_bitstream(attrs) do
          {:ok, thumb} -> {:ok, thumb}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Returns true if `item_id` already has a THUMBNAIL bitstream (user-uploaded
  cover or legacy FileCover). Used to decide whether auto-generation should
  be skipped.
  """
  def item_has_thumbnail?(item_id) when is_binary(item_id) do
    Repo.exists?(
      from b in Bitstream,
        where: b.item_id == ^item_id and b.bundle_name == :THUMBNAIL
    )
  end

  @doc """
  Returns the THUMBNAIL bitstream for `item_id`, or nil. Used by templates
  to render a cover image on item cards and detail pages.
  """
  def get_thumbnail_for_item(item_id) when is_binary(item_id) do
    Repo.one(
      from b in Bitstream,
        where: b.item_id == ^item_id and b.bundle_name == :THUMBNAIL,
        limit: 1
    )
  end
end
