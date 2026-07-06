defmodule Kiroku.Sync.Importer do
  @moduledoc """
  Single source of truth for processing records from the MSSQL legacy views.

  This module consolidates the record-processing logic that was previously
  duplicated (and diverged) between `mix kiroku.import_from_mssql` and
  `Kiroku.Workers.MssqlSyncWorker`. It is used by:

    - `Mix.Tasks.Kiroku.ImportFromMssql` — full import from the CLI
    - `Kiroku.Workers.MssqlSyncWorker` — incremental sync (cron + manual)
    - `Kiroku.Workers.ImportWorker` — full import triggered from the dashboard

  Records arrive as `Kiroku.LegacyView` structs loaded by Ecto, so fields use
  **atom keys** (`record.Judul`). Access helpers tolerate string keys too, for
  defensive use against any caller that hand-builds a map.
  """

  require Logger
  import Ecto.Query

  alias Kiroku.{Content, LegacyRepo, LegacyView, Repo, Repository, Sync}
  alias Kiroku.Repository.{Collection, Community}

  @root_handle "123456789/unpad-ta"
  @root_name "Tugas Akhir Mahasiswa Universitas Padjadjaran"

  @views [
    {"Skripsi", :skripsi},
    {"Tesis", :tesis},
    {"Disertasi", :disertasi},
    {"Tugas-Akhir", :tugas_akhir}
  ]

  def views, do: @views
  def valid_view?(name), do: Enum.any?(@views, fn {v, _} -> v == name end)

  @doc """
  Processes a single legacy view end-to-end.

  ## Options

    * `:dry_run` (default `false`) — parse and validate but write nothing.
    * `:incremental` (default `false`) — skip records that haven't changed
      since their last successful sync (uses checksum comparison).
    * `:sync_run` (default `nil`) — a `%Kiroku.Sync.SyncRun{}` to attach
      per-record tracking rows to. When omitted, no tracking is written.
    * `:batch_size` (default `100`) — streaming chunk size.
    * `:log` (default `false`) — emit per-record info logs.

  Returns a stats map:

      %{total: n, processed: n, inserted: n, updated: n, skipped: n, failed: n}

  """
  def run_view(view_name, opts \\ []) do
    dry_run? = Keyword.get(opts, :dry_run, false)
    incremental? = Keyword.get(opts, :incremental, false)
    sync_run = Keyword.get(opts, :sync_run)
    batch_size = Keyword.get(opts, :batch_size, 100)
    log? = Keyword.get(opts, :log, false)

    root = get_or_create_root_community(dry_run?)
    total = count_records(view_name)

    if log?, do: Logger.info("[Importer] #{view_name}: #{total} records found")

    initial = %{total: total, processed: 0, inserted: 0, updated: 0, skipped: 0, failed: 0}

    result =
      LegacyRepo.transaction(
        fn ->
          from(v in {view_name, LegacyView})
          |> LegacyRepo.stream(max_rows: batch_size)
          |> Enum.reduce({initial, %{}}, fn record, {acc, cache} ->
            process_record(record, cache, root, dry_run?, incremental?, sync_run, log?, acc)
          end)
        end,
        timeout: :infinity
      )

    case result do
      {:ok, {stats, _cache}} ->
        stats

      {:error, reason} ->
        Logger.error("[Importer] view #{view_name} transaction failed: #{inspect(reason)}")
        Map.merge(initial, %{failed: total})
    end
  end

  @doc """
  Returns the legacy_id of the most recent record in a view (by NPM desc).
  Used to populate `SyncRun.last_synced_legacy_id`.
  """
  def last_legacy_id(view_name) do
    record =
      LegacyRepo.one(
        from(v in {view_name, LegacyView},
          order_by: [desc: :NPM],
          limit: 1
        )
      )

    if record, do: build_legacy_id(field(record, :Jenis), field(record, :NPM)), else: nil
  end

  def count_records(view_name) do
    LegacyRepo.aggregate(from(v in {view_name, LegacyView}), :count, :NPM)
  end

  @doc """
  Processes a single record by NPM. Used by `Kiroku.Workers.SyncRetryWorker`
  to re-process dead-letter records. Assumes `LegacyRepo` is already started.

  Returns `{:ok, :inserted | :updated | :skipped}` or `{:error, reason}`.
  """
  def run_single(view_name, npm, opts \\ []) do
    dry_run? = Keyword.get(opts, :dry_run, false)
    sync_run = Keyword.get(opts, :sync_run)

    record =
      LegacyRepo.one(
        from(v in {view_name, LegacyView},
          where: field(v, :NPM) == ^npm,
          limit: 1
        )
      )

    case record do
      nil ->
        {:error, :not_found}

      record ->
        root = get_or_create_root_community(dry_run?)

        initial = %{total: 1, processed: 0, inserted: 0, updated: 0, skipped: 0, failed: 0}

        {stats, _cache} =
          process_record(record, %{}, root, dry_run?, false, sync_run, false, initial)

        cond do
          stats.failed > 0 -> {:error, :failed}
          stats.inserted > 0 -> {:ok, :inserted}
          stats.updated > 0 -> {:ok, :updated}
          stats.skipped > 0 -> {:ok, :skipped}
        end
    end
  end

  @doc """
  Splits a legacy_id (`"<slug>/<npm>"`) back into `{view_name, npm}`.

  The slug is the lowercased, hyphenated Jenis value, e.g. `"skripsi/12345"`
  resolves to `{"Skripsi", "12345"}`, `"tugas-akhir/12345"` to
  `{"Tugas-Akhir", "12345"}`. Returns `{nil, npm}` if the slug is unrecognized.
  """
  def parse_legacy_id(legacy_id) do
    case String.split(legacy_id, "/", parts: 2) do
      [slug, npm] -> {slug_to_view(slug), npm}
      [npm] -> {nil, npm}
    end
  end

  defp slug_to_view("skripsi"), do: "Skripsi"
  defp slug_to_view("tesis"), do: "Tesis"
  defp slug_to_view("disertasi"), do: "Disertasi"
  defp slug_to_view("tugas-akhir"), do: "Tugas-Akhir"
  defp slug_to_view(_), do: nil

  # ── Per-record processing ──────────────────────────────────────────────────

  defp process_record(record, cache, root, dry_run?, incremental?, sync_run, log?, acc) do
    judul = field(record, :Judul)

    cond do
      is_nil(judul) or String.trim(judul || "") == "" ->
        {%{acc | skipped: acc.skipped + 1}, cache}

      incremental? and not Sync.should_sync_record?(record, sync_run.source_view) ->
        {%{acc | skipped: acc.skipped + 1}, cache}

      true ->
        {status, new_cache} =
          upsert_record(record, cache, root, dry_run?, sync_run, log?)

        updated =
          case status do
            :inserted -> %{acc | inserted: acc.inserted + 1, processed: acc.processed + 1}
            :updated -> %{acc | updated: acc.updated + 1, processed: acc.processed + 1}
            :skipped -> %{acc | skipped: acc.skipped + 1}
            :error -> %{acc | failed: acc.failed + 1, processed: acc.processed + 1}
          end

        {updated, new_cache}
    end
  end

  defp upsert_record(record, cache, root, dry_run?, sync_run, log?) do
    fakultas = field(record, :Fakultas) || "Tidak Diketahui"
    jenjang = field(record, :Jenjang) || "Tidak Diketahui"
    program_studi = field(record, :Program_Studi) || "Tidak Diketahui"

    {new_cache, collection_id} = resolve_collection(cache, root, fakultas, jenjang, program_studi)

    item_type = map_item_type(field(record, :Jenis))
    attrs = build_item_attrs(record, item_type, collection_id)
    legacy_id = attrs.legacy_id
    checksum = Sync.calculate_record_checksum(record)

    cond do
      dry_run? ->
        if log? do
          Logger.info("[Importer] [DRY RUN] #{String.slice(attrs.title, 0, 70)}")
        end

        {:skipped, new_cache}

      true ->
        existing_item = Repository.get_item_by_handle(attrs.handle)
        action = if existing_item, do: :updated, else: :inserted

        case Repository.import_item(attrs) do
          {:ok, item} ->
            create_bitstreams_for_record(item, record)

            if sync_run do
              Sync.create_record_tracking(%{
                sync_run_id: sync_run.id,
                legacy_id: legacy_id,
                item_id: item.id,
                action: to_string(action),
                synced_at: DateTime.utc_now(),
                checksum: checksum
              })
            end

            {action, new_cache}

          {:error, changeset} ->
            npm = field(record, :NPM)

            Logger.warning(
              "[Importer] failed NPM=#{npm} legacy_id=#{legacy_id}: #{inspect(changeset.errors)}"
            )

            if sync_run do
              Sync.create_record_tracking(%{
                sync_run_id: sync_run.id,
                legacy_id: legacy_id,
                action: "failed",
                synced_at: DateTime.utc_now(),
                error_message: inspect(changeset.errors),
                checksum: checksum
              })
            end

            {:error, new_cache}
        end
    end
  end

  # ── Community / Collection hierarchy ───────────────────────────────────────

  defp get_or_create_root_community(true = _dry_run) do
    %Community{id: nil, name: @root_name}
  end

  defp get_or_create_root_community(false) do
    case Repo.get_by(Community, handle: @root_handle) do
      nil ->
        {:ok, c} =
          Repository.create_community(%{
            name: @root_name,
            handle: @root_handle,
            short_description: "Kumpulan tugas akhir mahasiswa Universitas Padjadjaran",
            is_active: true
          })

        Logger.info("[Importer] Created root community: #{@root_name}")
        c

      existing ->
        existing
    end
  end

  # Dry-run callers pass a root community with nil id; we short-circuit to a
  # nil collection so nothing is persisted. Real callers pass a persisted root.
  defp resolve_collection(cache, %Community{id: nil}, _fakultas, _jenjang, _program_studi) do
    {cache, nil}
  end

  defp resolve_collection(cache, root, fakultas, jenjang, program_studi) do
    fak_key = {:fak, fakultas}
    jenjang_key = {:jenjang, fakultas, jenjang}
    coll_key = {:coll, fakultas, jenjang, program_studi}

    {cache, fak_id} =
      case Map.get(cache, fak_key) do
        nil ->
          c = get_or_create_fakultas(root.id, fakultas)
          {Map.put(cache, fak_key, c.id), c.id}

        id ->
          {cache, id}
      end

    {cache, jenjang_id} =
      case Map.get(cache, jenjang_key) do
        nil ->
          c = get_or_create_jenjang(fak_id, fakultas, jenjang)
          {Map.put(cache, jenjang_key, c.id), c.id}

        id ->
          {cache, id}
      end

    {cache, coll_id} =
      case Map.get(cache, coll_key) do
        nil ->
          coll = get_or_create_prodi_collection(jenjang_id, fakultas, jenjang, program_studi)
          {Map.put(cache, coll_key, coll.id), coll.id}

        id ->
          {cache, id}
      end

    {cache, coll_id}
  end

  defp get_or_create_fakultas(root_id, fakultas) do
    handle = "123456789/fak-#{slugify(fakultas)}"

    case Repo.get_by(Community, handle: handle) do
      nil ->
        {:ok, c} =
          Repository.create_community(%{
            name: "Fakultas #{fakultas}",
            handle: handle,
            parent_community_id: root_id,
            is_active: true
          })

        Logger.info("[Importer]   + Fakultas #{fakultas}")
        c

      existing ->
        existing
    end
  end

  defp get_or_create_jenjang(fakultas_id, fakultas, jenjang) do
    handle = "123456789/fak-#{slugify(fakultas)}/#{slugify(jenjang)}"

    case Repo.get_by(Community, handle: handle) do
      nil ->
        {:ok, c} =
          Repository.create_community(%{
            name: jenjang,
            handle: handle,
            parent_community_id: fakultas_id,
            is_active: true
          })

        Logger.info("[Importer]     + #{jenjang} (Fakultas #{fakultas})")
        c

      existing ->
        existing
    end
  end

  defp get_or_create_prodi_collection(jenjang_id, fakultas, jenjang, program_studi) do
    handle =
      "123456789/fak-#{slugify(fakultas)}/#{slugify(jenjang)}/#{slugify(program_studi)}"

    collection_name = "#{jenjang} #{program_studi}"

    case Repo.get_by(Collection, handle: handle) do
      nil ->
        {:ok, coll} =
          Repository.create_collection(%{
            name: collection_name,
            handle: handle,
            community_id: jenjang_id,
            is_active: true
          })

        Logger.info("[Importer]       + Collection: #{collection_name}")
        coll

      existing ->
        existing
    end
  end

  # ── Item attributes + bitstreams ───────────────────────────────────────────

  defp build_item_attrs(r, item_type, collection_id) do
    npm = field(r, :NPM)
    idpustaka = field(r, :idpustaka)

    status =
      map_status(
        field(r, :stPublikasi),
        field(r, :Verifikasi),
        parse_validasi(field(r, :Validasi))
      )

    %{
      handle: build_handle(idpustaka, npm),
      legacy_id: build_legacy_id(field(r, :Jenis), npm),
      idpustaka: idpustaka,
      title: field(r, :Judul),
      abstract: field(r, :Abstrak),
      language: :id,
      student_id: npm,
      student_name: field(r, :Nama),
      faculty: field(r, :Fakultas),
      department: field(r, :Kode),
      program_study: field(r, :Program_Studi),
      degree_level: map_degree(field(r, :Jenjang)),
      item_type: item_type,
      date_submitted: date_from_datetime(field(r, :Tgl_Upload)),
      subject_classification: field(r, :TagPustaka),
      status: status,
      discoverable: status == :published,
      access_level: :open,
      base_url: field(r, :LinkPath),
      institution: institution_name(),
      collection_id: collection_id
    }
  end

  defp create_bitstreams_for_record(item, r) do
    link_path = field(r, :LinkPath)

    file_map = [
      {field(r, :FileCover), :THUMBNAIL, 1, :open},
      {field(r, :FileAbstrak), :ORIGINAL, 1, :inherit},
      {field(r, :FileBab1), :CHAPTER, 1, :inherit},
      {field(r, :FileBab2), :CHAPTER, 2, :inherit},
      {field(r, :FileBab3), :CHAPTER, 3, :inherit},
      {field(r, :FileBab4), :CHAPTER, 4, :inherit},
      {field(r, :FileBab5), :CHAPTER, 5, :inherit},
      {field(r, :FileBab6), :CHAPTER, 6, :inherit},
      {field(r, :FileDaftarIsi), :SUPPLEMENTAL, 1, :inherit},
      {field(r, :FilePustaka), :SUPPLEMENTAL, 2, :inherit},
      {field(r, :FileLampiran), :SUPPLEMENTAL, 3, :inherit},
      {field(r, :FilePengesahan), :ADMINISTRATIVE, 1, :restricted},
      {field(r, :FileSurat), :ADMINISTRATIVE, 2, :restricted},
      {field(r, :FileSuratIsi), :ADMINISTRATIVE, 3, :restricted}
    ]

    Enum.each(file_map, fn {file_col, bundle, seq, access} ->
      if not is_nil(file_col) and file_col != "" do
        attrs = %{
          item_id: item.id,
          filename: Path.basename(file_col),
          bundle_name: bundle,
          sequence: seq,
          description: legacy_file_description(bundle, seq),
          storage_type: :url,
          storage_url: build_file_url(link_path, file_col),
          access_level: access,
          embargo_open_date: item.embargo_open_date
        }

        case Content.create_bitstream(attrs) do
          {:ok, _} ->
            :ok

          {:error, reason} ->
            Logger.warning(
              "[Importer] bitstream failed item=#{item.id} #{bundle}/#{seq}: #{inspect(reason)}"
            )
        end
      end
    end)
  end

  # ── Mapping helpers ────────────────────────────────────────────────────────

  defp map_item_type("Skripsi"), do: :skripsi
  defp map_item_type("Tesis"), do: :tesis
  defp map_item_type("Disertasi"), do: :disertasi
  defp map_item_type("Tugas Akhir"), do: :tugas_akhir
  defp map_item_type(_), do: :skripsi

  defp map_degree("Sarjana"), do: :s1
  defp map_degree("Sarjana Terapan"), do: :s1_terapan
  defp map_degree("Magister"), do: :s2
  defp map_degree("Doktor"), do: :s3
  defp map_degree("Diploma III"), do: :d3
  defp map_degree("Diploma IV"), do: :d4
  defp map_degree(_), do: nil

  # Validasi is VARCHAR in the legacy views — may hold integers ("1") or
  # library-approval strings ("pustaka"). Anything non-zero counts as validated.
  defp parse_validasi(nil), do: 0
  defp parse_validasi(v) when is_integer(v), do: v

  defp parse_validasi(v) when is_binary(v) do
    case Integer.parse(String.trim(v)) do
      {n, _} -> n
      :error -> if String.length(v) > 0, do: 1, else: 0
    end
  end

  defp map_status(1, 1, v) when v >= 1, do: :published
  defp map_status(1, 1, _), do: :under_review
  defp map_status(1, _, _), do: :submitted
  defp map_status(_, _, _), do: :submitted

  defp build_handle(nil, npm), do: "123456789/legacy-#{npm}"
  defp build_handle("", npm), do: "123456789/legacy-#{npm}"
  defp build_handle(h, _), do: h

  defp build_legacy_id(nil, npm), do: "unknown/#{npm}"
  defp build_legacy_id("", npm), do: "unknown/#{npm}"

  defp build_legacy_id(jenis, npm) do
    slug = (jenis || "unknown") |> String.downcase() |> String.replace(" ", "-")
    "#{slug}/#{npm}"
  end

  defp build_file_url(nil, file_col), do: file_col
  defp build_file_url("", file_col), do: file_col

  defp build_file_url(base, file_col) do
    base = String.trim_trailing(base, "/")
    file = String.trim_leading(file_col, "/")
    "#{base}/#{file}"
  end

  defp date_from_datetime(nil), do: nil
  defp date_from_datetime(dt), do: DateTime.to_date(dt)

  defp legacy_file_description(:THUMBNAIL, _), do: "Cover image"
  defp legacy_file_description(:ORIGINAL, 1), do: "Abstract"
  defp legacy_file_description(:ORIGINAL, _), do: "Full text"
  defp legacy_file_description(:CHAPTER, seq), do: "Bab #{seq}"
  defp legacy_file_description(:SUPPLEMENTAL, 1), do: "Daftar isi"
  defp legacy_file_description(:SUPPLEMENTAL, 2), do: "Daftar pustaka"
  defp legacy_file_description(:SUPPLEMENTAL, 3), do: "Lampiran"
  defp legacy_file_description(:ADMINISTRATIVE, 1), do: "Lembar pengesahan"
  defp legacy_file_description(:ADMINISTRATIVE, 2), do: "Surat pengantar"
  defp legacy_file_description(:ADMINISTRATIVE, 3), do: "Surat pengantar (isi)"
  defp legacy_file_description(_, _), do: "Document"

  defp slugify(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/[\s-]+/, "-")
    |> String.trim("-")
  end

  defp institution_name do
    Application.get_env(:kiroku, :institution_name, "Universitas Padjadjaran")
  end

  # Key-agnostic field accessor. `Kiroku.LegacyView` is an Ecto schema so records
  # arrive with atom keys, but we tolerate string-keyed maps defensively.
  defp field(record, key) when is_atom(key) do
    Map.get(record, key) || Map.get(record, Atom.to_string(key))
  end
end
