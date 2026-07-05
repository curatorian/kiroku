defmodule Kiroku.Workers.MssqlSyncWorker do
  @moduledoc """
  Background worker for incremental MSSQL synchronization.
  Processes changed records from legacy views and updates PostgreSQL.
  """

  use Oban.Worker, queue: :sync, max_attempts: 3, unique: [period: 300]

  require Logger
  import Ecto.Query

  alias Kiroku.{Repo, Sync, LegacyRepo, LegacyView, Repository}
  alias Kiroku.Repository.{Community, Collection}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"view" => view_name}} = job) do
    Logger.info("Starting incremental sync for view: #{view_name}")

    # Start legacy repo if not already started
    case LegacyRepo.start_link() do
      {:ok, _} ->
        :ok

      {:error, {:already_started, _}} ->
        :ok

      {:error, reason} ->
        Logger.error("Cannot start LegacyRepo: #{inspect(reason)}")
        return_error(job, "Failed to start LegacyRepo: #{inspect(reason)}")
    end

    # Create sync run for tracking
    {:ok, sync_run} = Sync.start_sync_run(view_name)

    try do
      # Get sync position (last sync time and legacy ID)
      position = Sync.get_sync_position(view_name)

      # Build or fetch the root community
      root = get_or_create_root_community()

      # Process records with change detection
      stats = process_incremental_sync(view_name, position, root, sync_run)

      # Complete sync run
      Sync.complete_sync_run(sync_run, %{
        processed: stats.processed,
        inserted: stats.inserted,
        updated: stats.updated,
        failed: stats.failed,
        last_synced_at: DateTime.utc_now(),
        last_synced_legacy_id: get_last_legacy_id(view_name)
      })

      Logger.info("Incremental sync completed for #{view_name}: #{inspect(stats)}")
      :ok
    rescue
      error ->
        Logger.error("Incremental sync failed for #{view_name}: #{inspect(error)}")
        Sync.fail_sync_run(sync_run, inspect(error))
        return_error(job, inspect(error))
    end
  end

  defp process_incremental_sync(view_name, _position, root, sync_run) do
    _total = LegacyRepo.aggregate(from(v in {view_name, LegacyView}), :count, :NPM)

    initial_stats = %{
      processed: 0,
      inserted: 0,
      updated: 0,
      skipped: 0,
      failed: 0
    }

    # Stream records and process only changed ones
    {final_stats, _cache} =
      LegacyRepo.transaction(
        fn ->
          from(v in {view_name, LegacyView})
          |> LegacyRepo.stream(max_rows: 100)
          |> Enum.reduce({initial_stats, %{}}, fn record, {stats, cache} ->
            if Sync.should_sync_record?(record, view_name) do
              {action, new_cache} = sync_record(record, cache, root, sync_run)

              updated_stats =
                case action do
                  :inserted ->
                    %{stats | inserted: stats.inserted + 1, processed: stats.processed + 1}

                  :updated ->
                    %{stats | updated: stats.updated + 1, processed: stats.processed + 1}

                  :skipped ->
                    %{stats | skipped: stats.skipped + 1}

                  :error ->
                    %{stats | failed: stats.failed + 1, processed: stats.processed + 1}
                end

              {updated_stats, new_cache}
            else
              {%{stats | skipped: stats.skipped + 1}, cache}
            end
          end)
        end,
        timeout: :infinity
      )

    final_stats
  end

  defp sync_record(record, cache, root, sync_run) do
    judul = Map.get(record, "Judul")

    if is_nil(judul) or String.trim(judul || "") == "" do
      {:skipped, cache}
    else
      fakultas = Map.get(record, "Fakultas") || "Tidak Diketahui"
      jenjang = Map.get(record, "Jenjang") || "Tidak Diketahui"
      program_studi = Map.get(record, "Program_Studi") || "Tidak Diketahui"

      {new_cache, collection_id} =
        resolve_collection(cache, root, fakultas, jenjang, program_studi)

      item_type = map_item_type(Map.get(record, "Jenis"))
      attrs = build_item_attrs(record, item_type, collection_id)
      legacy_id = attrs.legacy_id
      checksum = Sync.calculate_record_checksum(record)

      # Check if this is an update or insert
      existing_item = Repository.get_item_by_handle(attrs.handle)
      action = if existing_item, do: :updated, else: :inserted

      case Repository.import_item(attrs) do
        {:ok, item} ->
          create_bitstreams_for_record(item, record)

          # Track the sync record
          Sync.create_record_tracking(%{
            sync_run_id: sync_run.id,
            legacy_id: legacy_id,
            item_id: item.id,
            action: to_string(action),
            synced_at: DateTime.utc_now(),
            checksum: checksum
          })

          {action, new_cache}

        {:error, changeset} ->
          Logger.warning("Sync failed for legacy_id=#{legacy_id}: #{inspect(changeset.errors)}")

          # Track failed record
          Sync.create_record_tracking(%{
            sync_run_id: sync_run.id,
            legacy_id: legacy_id,
            action: "failed",
            synced_at: DateTime.utc_now(),
            error_message: inspect(changeset.errors),
            checksum: checksum
          })

          {:error, new_cache}
      end
    end
  end

  # Community/Collection resolution helpers
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

  defp get_or_create_root_community do
    root_handle = "123456789/unpad-ta"
    root_name = "Tugas Akhir Mahasiswa Universitas Padjadjaran"

    case Repo.get_by(Community, handle: root_handle) do
      nil ->
        {:ok, c} =
          Repository.create_community(%{
            name: root_name,
            handle: root_handle,
            short_description: "Kumpulan tugas akhir mahasiswa Universitas Padjadjaran",
            is_active: true
          })

        Logger.info("Created root community: #{root_name}")
        c

      existing ->
        existing
    end
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

        c

      existing ->
        existing
    end
  end

  defp get_or_create_prodi_collection(jenjang_id, fakultas, jenjang, program_studi) do
    handle = "123456789/fak-#{slugify(fakultas)}/#{slugify(jenjang)}/#{slugify(program_studi)}"
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

        coll

      existing ->
        existing
    end
  end

  # Attribute builders
  defp build_item_attrs(r, item_type, collection_id) do
    npm = Map.get(r, "NPM")
    idpustaka = Map.get(r, "idpustaka")

    status =
      map_status(
        Map.get(r, "stPublikasi"),
        Map.get(r, "Verifikasi"),
        parse_validasi(Map.get(r, "Validasi"))
      )

    handle = build_handle(idpustaka, npm)

    %{
      handle: handle,
      legacy_id: build_legacy_id(Map.get(r, "Jenis"), npm),
      idpustaka: idpustaka,
      title: Map.get(r, "Judul"),
      abstract: Map.get(r, "Abstrak"),
      language: :id,
      student_id: npm,
      student_name: Map.get(r, "Nama"),
      faculty: Map.get(r, "Fakultas"),
      department: Map.get(r, "Kode"),
      program_study: Map.get(r, "Program_Studi"),
      degree_level: map_degree(Map.get(r, "Jenjang")),
      item_type: item_type,
      date_submitted: date_from_datetime(Map.get(r, "Tgl_Upload")),
      subject_classification: Map.get(r, "TagPustaka"),
      status: status,
      discoverable: status == :published,
      access_level: :open,
      base_url: Map.get(r, "LinkPath"),
      institution: institution_name(),
      collection_id: collection_id
    }
  end

  defp create_bitstreams_for_record(item, r) do
    link_path = Map.get(r, "LinkPath")

    file_map = [
      {Map.get(r, "FileCover"), :THUMBNAIL, 1, :open},
      {Map.get(r, "FileAbstrak"), :ORIGINAL, 1, :inherit},
      {Map.get(r, "FileBab1"), :CHAPTER, 1, :inherit},
      {Map.get(r, "FileBab2"), :CHAPTER, 2, :inherit},
      {Map.get(r, "FileBab3"), :CHAPTER, 3, :inherit},
      {Map.get(r, "FileBab4"), :CHAPTER, 4, :inherit},
      {Map.get(r, "FileBab5"), :CHAPTER, 5, :inherit},
      {Map.get(r, "FileBab6"), :CHAPTER, 6, :inherit},
      {Map.get(r, "FileDaftarIsi"), :SUPPLEMENTAL, 1, :inherit},
      {Map.get(r, "FilePustaka"), :SUPPLEMENTAL, 2, :inherit},
      {Map.get(r, "FileLampiran"), :SUPPLEMENTAL, 3, :inherit},
      {Map.get(r, "FilePengesahan"), :ADMINISTRATIVE, 1, :restricted},
      {Map.get(r, "FileSurat"), :ADMINISTRATIVE, 2, :restricted},
      {Map.get(r, "FileSuratIsi"), :ADMINISTRATIVE, 3, :restricted}
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
          access_level: access
        }

        Kiroku.Content.create_bitstream(attrs)
      end
    end)
  end

  # Helper functions
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

  defp get_last_legacy_id(view_name) do
    record =
      LegacyRepo.one(
        from(v in {view_name, LegacyView},
          order_by: [desc: :NPM],
          limit: 1
        )
      )

    if record, do: build_legacy_id(record["Jenis"], record["NPM"]), else: nil
  end

  defp return_error(_job, reason) do
    # Log the error and mark the job as failed
    Logger.error("Sync job failed: #{reason}")
    {:error, reason}
  end
end
