defmodule Kiroku.Workers.SyncRetryWorker do
  @moduledoc """
  Worker for retrying failed sync records from the dead-letter queue.
  Implements exponential backoff and intelligent retry strategies.
  """

  use Oban.Worker, queue: :sync_retries, max_attempts: 5, unique: [period: 60]

  require Logger
  import Ecto.Query
  alias Kiroku.{Repo, LegacyRepo, LegacyView, Repository}
  alias Kiroku.Sync.ErrorHandler
  alias Kiroku.Sync.DeadLetterQueue

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"legacy_id" => legacy_id} = args}) do
    sync_run_id = Map.get(args, "sync_run_id")
    attempt = Map.get(args, "attempt", 1)

    Logger.info("Retrying sync for legacy_id: #{legacy_id} (attempt #{attempt})")

    # Get the dead letter queue entry
    dead_letter = Repo.get_by(DeadLetterQueue, legacy_id: legacy_id)

    if dead_letter do
      retry_dead_letter_record(dead_letter, sync_run_id, attempt)
    else
      Logger.warning("Dead letter entry not found for #{legacy_id}, attempting direct sync")
      retry_direct_sync(legacy_id, sync_run_id, attempt)
    end
  end

  defp retry_dead_letter_record(dead_letter, _sync_run_id, attempt) do
    # Determine the view from the legacy_id
    {view_name, npm} = parse_legacy_id(dead_letter.legacy_id)

    # Start legacy repo if not already started
    case LegacyRepo.start_link() do
      {:ok, _} ->
        :ok

      {:error, {:already_started, _}} ->
        :ok

      {:error, reason} ->
        Logger.error("Cannot start LegacyRepo: #{inspect(reason)}")
        return_error(reason)
    end

    # Fetch the record from MSSQL
    record =
      LegacyRepo.one(
        from(v in {view_name, LegacyView},
          where: field(v, :NPM) == ^npm,
          limit: 1
        )
      )

    if record do
      try do
        # Attempt to sync the record
        result = sync_single_record(record, dead_letter)

        case result do
          {:ok, _} ->
            # Mark as resolved
            dead_letter
            |> Ecto.Changeset.change(%{
              resolved_at: DateTime.utc_now(),
              resolution_notes: "Successfully synced on attempt #{attempt}",
              retry_count: attempt
            })
            |> Repo.update()

            Logger.info("Successfully resolved dead letter record: #{dead_letter.legacy_id}")
            :ok

          {:error, reason} ->
            handle_retry_failure(dead_letter, reason, attempt)
        end
      rescue
        error ->
          handle_retry_failure(dead_letter, error, attempt)
      end
    else
      Logger.error("Record not found in MSSQL for #{dead_letter.legacy_id}")
      handle_retry_failure(dead_letter, "Record not found in source", attempt)
    end
  end

  defp retry_direct_sync(legacy_id, _sync_run_id, _attempt) do
    {view_name, npm} = parse_legacy_id(legacy_id)

    # Start legacy repo if not already started
    case LegacyRepo.start_link() do
      {:ok, _} ->
        :ok

      {:error, {:already_started, _}} ->
        :ok

      {:error, reason} ->
        Logger.error("Cannot start LegacyRepo: #{inspect(reason)}")
        return_error(reason)
    end

    # Fetch the record from MSSQL
    record =
      LegacyRepo.one(
        from(v in {view_name, LegacyView},
          where: field(v, :NPM) == ^npm,
          limit: 1
        )
      )

    if record do
      try do
        # Attempt to sync the record
        result = sync_single_record(record, nil)

        case result do
          {:ok, _} ->
            Logger.info("Successfully synced record: #{legacy_id}")
            :ok

          {:error, reason} ->
            Logger.error("Retry failed for #{legacy_id}: #{inspect(reason)}")
            return_error(reason)
        end
      rescue
        error ->
          Logger.error("Retry failed with exception for #{legacy_id}: #{inspect(error)}")
          return_error(error)
      end
    else
      Logger.error("Record not found in MSSQL for #{legacy_id}")
      return_error("Record not found in source")
    end
  end

  defp sync_single_record(record, _dead_letter) do
    # Get root community
    root = get_or_create_root_community()

    # Resolve collection
    fakultas = Map.get(record, "Fakultas") || "Tidak Diketahui"
    jenjang = Map.get(record, "Jenjang") || "Tidak Diketahui"
    program_studi = Map.get(record, "Program_Studi") || "Tidak Diketahui"

    {_, collection_id} = resolve_collection(%{}, root, fakultas, jenjang, program_studi)

    # Build item attributes
    item_type = map_item_type(Map.get(record, "Jenis"))
    attrs = build_item_attrs(record, item_type, collection_id)

    # Import item
    Repository.import_item(attrs)
  end

  defp handle_retry_failure(dead_letter, reason, attempt) do
    # Update dead letter entry
    dead_letter
    |> Ecto.Changeset.change(%{
      retry_count: attempt,
      last_attempted_at: DateTime.utc_now(),
      error_message: inspect(reason)
    })
    |> Repo.update()

    # Use error handler to determine next action
    ErrorHandler.handle_failed_record(
      dead_letter.sync_run_id,
      dead_letter.legacy_id,
      reason,
      attempt + 1
    )
  end

  defp resolve_collection(cache, root, fakultas, jenjang, program_studi) do
    # Simplified version - in production use the full implementation
    # Get or create fakultas community
    fak_key = {:fak, fakultas}

    {cache, fak_id} =
      case Map.get(cache, fak_key) do
        nil ->
          c = get_or_create_fakultas(root.id, fakultas)
          {Map.put(cache, fak_key, c.id), c.id}

        id ->
          {cache, id}
      end

    # Get or create jenjang community
    jenjang_key = {:jenjang, fakultas, jenjang}

    {cache, jenjang_id} =
      case Map.get(cache, jenjang_key) do
        nil ->
          c = get_or_create_jenjang(fak_id, fakultas, jenjang)
          {Map.put(cache, jenjang_key, c.id), c.id}

        id ->
          {cache, id}
      end

    # Get or create collection
    coll_key = {:coll, fakultas, jenjang, program_studi}

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

    case Repo.get_by(Kiroku.Repository.Community, handle: root_handle) do
      nil ->
        {:ok, c} =
          Repository.create_community(%{
            name: root_name,
            handle: root_handle,
            short_description: "Kumpulan tugas akhir mahasiswa Universitas Padjadjaran",
            is_active: true
          })

        c

      existing ->
        existing
    end
  end

  defp get_or_create_fakultas(root_id, fakultas) do
    handle = "123456789/fak-#{slugify(fakultas)}"

    case Repo.get_by(Kiroku.Repository.Community, handle: handle) do
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

    case Repo.get_by(Kiroku.Repository.Community, handle: handle) do
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

    case Repo.get_by(Kiroku.Repository.Collection, handle: handle) do
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
      institution: Application.get_env(:kiroku, :institution_name, "Universitas Padjadjaran"),
      collection_id: collection_id
    }
  end

  defp parse_legacy_id(legacy_id) do
    case String.split(legacy_id, "/") do
      [jenis, npm] -> {jenis, npm}
      _ -> {"unknown", legacy_id}
    end
  end

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

  defp date_from_datetime(nil), do: nil
  defp date_from_datetime(dt), do: DateTime.to_date(dt)

  defp slugify(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/[\s-]+/, "-")
    |> String.trim("-")
  end

  defp return_error(reason) do
    Logger.error("Retry job failed: #{inspect(reason)}")
    {:error, reason}
  end
end
