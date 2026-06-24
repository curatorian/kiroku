defmodule Mix.Tasks.Kiroku.ImportFromMssql do
  use Mix.Task

  @shortdoc "Import legacy thesis records from MSSQL views into Kiroku PostgreSQL"

  @moduledoc """
  Reads records from the four MSSQL legacy views and upserts them into Kiroku.

  The community / collection hierarchy is built automatically from the data:

      Tugas Akhir Mahasiswa Universitas Padjadjaran   (root community)
      └─ Fakultas <X>                                 (sub-community)
          └─ <Jenjang>                                (sub-community)
              └─ <Jenjang> <Program_Studi>            (collection — items land here)

  Views read (all share the same column layout):
      dbo.Skripsi, dbo.Tesis, dbo.Disertasi, dbo.Tugas-Akhir

  Usage:
      mix kiroku.import_from_mssql
      mix kiroku.import_from_mssql --dry-run
      mix kiroku.import_from_mssql --batch-size 500
      mix kiroku.import_from_mssql --view Skripsi     (import one view only)

  Options:
    --dry-run         Parse and validate but do not persist.
    --batch-size N    Stream records in batches of N (default 100).
    --view NAME       Import only this view (Skripsi / Tesis / Disertasi / Tugas-Akhir).
  """

  import Ecto.Query
  require Logger

  alias Kiroku.{Repo, Content}
  alias Kiroku.LegacyRepo
  alias Kiroku.LegacyView
  alias Kiroku.Repository
  alias Kiroku.Repository.{Community, Collection}

  @requirements ["app.start"]

  # View name  →  default item_type (overridden per-row by Jenis column)
  @views [
    {"Skripsi", :skripsi},
    {"Tesis", :tesis},
    {"Disertasi", :disertasi},
    {"Tugas-Akhir", :tugas_akhir}
  ]

  @root_handle "123456789/unpad-ta"
  @root_name "Tugas Akhir Mahasiswa Universitas Padjadjaran"

  # ── Entry point ────────────────────────────────────────────────────────────

  def run(args) do
    opts = parse_opts(args)
    batch_size = Keyword.get(opts, :batch_size, 100)
    dry_run? = Keyword.get(opts, :dry_run, false)
    only_view = Keyword.get(opts, :view)

    Mix.shell().info("Starting LegacyRepo…")

    case LegacyRepo.start_link() do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
      {:error, reason} -> Mix.raise("Cannot start LegacyRepo: #{inspect(reason)}")
    end

    if dry_run?, do: Mix.shell().info("[DRY RUN] — no database writes will occur")

    views_to_run =
      case only_view do
        nil -> @views
        name -> Enum.filter(@views, fn {v, _} -> v == name end)
      end

    if views_to_run == [] do
      valid = Enum.map_join(@views, ", ", fn {v, _} -> v end)
      Mix.raise("No matching view. Valid values: #{valid}")
    end

    # Build or fetch the root community once
    root = get_or_create_root_community(dry_run?)

    # Process each view, carrying the community/collection cache forward
    {final_stats, _cache} =
      Enum.reduce(
        views_to_run,
        {%{inserted: 0, skipped: 0, errors: 0}, %{}},
        fn {view_name, _default_type}, {stats, cache} ->
          Mix.shell().info("\n── View: #{view_name} ──")
          import_view(view_name, stats, cache, root, batch_size, dry_run?)
        end
      )

    Mix.shell().info("""

    Import complete.
      Inserted / updated : #{final_stats.inserted}
      Skipped            : #{final_stats.skipped}
      Errors             : #{final_stats.errors}
    """)
  end

  # ── Per-view import ────────────────────────────────────────────────────────

  defp import_view(view_name, stats, cache, root, batch_size, dry_run?) do
    total = LegacyRepo.aggregate(from(v in {view_name, LegacyView}), :count, :NPM)
    Mix.shell().info("  #{total} records found")

    result =
      LegacyRepo.transaction(
        fn ->
          from(v in {view_name, LegacyView})
          |> LegacyRepo.stream(max_rows: batch_size)
          |> Enum.reduce({stats, cache}, fn record, {inner_stats, inner_cache} ->
            {status, new_cache} = import_record(record, inner_cache, root, dry_run?)

            updated =
              case status do
                :inserted -> Map.update!(inner_stats, :inserted, &(&1 + 1))
                :skipped -> Map.update!(inner_stats, :skipped, &(&1 + 1))
                :error -> Map.update!(inner_stats, :errors, &(&1 + 1))
              end

            {updated, new_cache}
          end)
        end,
        timeout: :infinity
      )

    case result do
      {:ok, {new_stats, new_cache}} ->
        Mix.shell().info("  Done — #{new_stats.inserted - stats.inserted} upserted")
        {new_stats, new_cache}

      {:error, reason} ->
        Mix.shell().error("  View #{view_name} failed: #{inspect(reason)}")
        {stats, cache}
    end
  end

  # ── Single record ──────────────────────────────────────────────────────────

  defp import_record(r, cache, root, dry_run?) do
    judul = Map.get(r, :Judul)

    if is_nil(judul) or String.trim(judul || "") == "" do
      {:skipped, cache}
    else
      fakultas = Map.get(r, :Fakultas) || "Tidak Diketahui"
      jenjang = Map.get(r, :Jenjang) || "Tidak Diketahui"
      program_studi = Map.get(r, :Program_Studi) || "Tidak Diketahui"

      {new_cache, collection_id} =
        resolve_collection(cache, root, fakultas, jenjang, program_studi, dry_run?)

      item_type = map_item_type(Map.get(r, :Jenis))
      attrs = build_item_attrs(r, item_type, collection_id)

      cond do
        dry_run? ->
          npm = Map.get(r, :NPM)
          Mix.shell().info("  [DRY RUN] #{String.slice(judul, 0, 70)} (NPM=#{npm})")
          {:skipped, new_cache}

        true ->
          case Repository.import_item(attrs) do
            {:ok, item} ->
              create_bitstreams_for_record(item, r)
              {:inserted, new_cache}

            {:error, changeset} ->
              npm = Map.get(r, :NPM)
              Logger.warning("Import failed NPM=#{npm}: #{inspect(changeset.errors)}")
              {:error, new_cache}
          end
      end
    end
  end

  # ── Community / Collection hierarchy ──────────────────────────────────────

  defp get_or_create_root_community(dry_run?) do
    if dry_run? do
      %Community{id: nil, name: @root_name}
    else
      case Repo.get_by(Community, handle: @root_handle) do
        nil ->
          {:ok, c} =
            Repository.create_community(%{
              name: @root_name,
              handle: @root_handle,
              short_description: "Kumpulan tugas akhir mahasiswa Universitas Padjadjaran",
              is_active: true
            })

          Mix.shell().info("Created root community: #{@root_name}")
          c

        existing ->
          existing
      end
    end
  end

  # Returns {updated_cache, collection_id}
  defp resolve_collection(cache, _root, _fakultas, _jenjang, _program_studi, true = _dry_run) do
    {cache, nil}
  end

  defp resolve_collection(cache, root, fakultas, jenjang, program_studi, false) do
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
    handle = "123456789/fak-#{Slug.slugify(fakultas)}"

    case Repo.get_by(Community, handle: handle) do
      nil ->
        {:ok, c} =
          Repository.create_community(%{
            name: "Fakultas #{fakultas}",
            handle: handle,
            parent_community_id: root_id,
            is_active: true
          })

        Mix.shell().info("  + Community: Fakultas #{fakultas}")
        c

      existing ->
        existing
    end
  end

  defp get_or_create_jenjang(fakultas_id, fakultas, jenjang) do
    handle = "123456789/fak-#{Slug.slugify(fakultas)}/#{Slug.slugify(jenjang)}"

    case Repo.get_by(Community, handle: handle) do
      nil ->
        {:ok, c} =
          Repository.create_community(%{
            name: jenjang,
            handle: handle,
            parent_community_id: fakultas_id,
            is_active: true
          })

        Mix.shell().info("    + Community: #{jenjang} (Fakultas #{fakultas})")
        c

      existing ->
        existing
    end
  end

  defp get_or_create_prodi_collection(jenjang_id, fakultas, jenjang, program_studi) do
    handle =
      "123456789/fak-#{Slug.slugify(fakultas)}/#{Slug.slugify(jenjang)}/#{Slug.slugify(program_studi)}"

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

        Mix.shell().info("      + Collection: #{collection_name}")
        coll

      existing ->
        existing
    end
  end

  # ── Attribute builder ──────────────────────────────────────────────────────

  defp build_item_attrs(r, item_type, collection_id) do
    npm = Map.get(r, :NPM)
    idpustaka = r.idpustaka

    status =
      map_status(r.stPublikasi, Map.get(r, :Verifikasi), parse_validasi(Map.get(r, :Validasi)))

    handle = build_handle(idpustaka, npm)

    %{
      handle: handle,
      legacy_id: build_legacy_id(Map.get(r, :Jenis), npm),
      idpustaka: idpustaka,
      title: Map.get(r, :Judul),
      abstract: Map.get(r, :Abstrak),
      language: :id,
      student_id: npm,
      student_name: Map.get(r, :Nama),
      faculty: Map.get(r, :Fakultas),
      department: Map.get(r, :Kode),
      program_study: Map.get(r, :Program_Studi),
      degree_level: map_degree(Map.get(r, :Jenjang)),
      item_type: item_type,
      date_submitted: date_from_datetime(Map.get(r, :Tgl_Upload)),
      subject_classification: Map.get(r, :TagPustaka),
      status: status,
      discoverable: status == :published,
      access_level: :open,
      base_url: Map.get(r, :LinkPath),
      institution: institution_name(),
      collection_id: collection_id
    }
  end

  defp create_bitstreams_for_record(item, r) do
    link_path = Map.get(r, :LinkPath)

    file_map = [
      {Map.get(r, :FileCover), :THUMBNAIL, 1, :open},
      {Map.get(r, :FileAbstrak), :ORIGINAL, 1, :inherit},
      {Map.get(r, :FileBab1), :CHAPTER, 1, :inherit},
      {Map.get(r, :FileBab2), :CHAPTER, 2, :inherit},
      {Map.get(r, :FileBab3), :CHAPTER, 3, :inherit},
      {Map.get(r, :FileBab4), :CHAPTER, 4, :inherit},
      {Map.get(r, :FileBab5), :CHAPTER, 5, :inherit},
      {Map.get(r, :FileBab6), :CHAPTER, 6, :inherit},
      {Map.get(r, :FileDaftarIsi), :SUPPLEMENTAL, 1, :inherit},
      {Map.get(r, :FilePustaka), :SUPPLEMENTAL, 2, :inherit},
      {Map.get(r, :FileLampiran), :SUPPLEMENTAL, 3, :inherit},
      {Map.get(r, :FilePengesahan), :ADMINISTRATIVE, 1, :restricted},
      {Map.get(r, :FileSurat), :ADMINISTRATIVE, 2, :restricted},
      {Map.get(r, :FileSuratIsi), :ADMINISTRATIVE, 3, :restricted}
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
              "Bitstream failed item=#{item.id} #{bundle}/#{seq}: #{inspect(reason)}"
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

  # Validasi in legacy views is VARCHAR — may contain integers ("1") or
  # library-approval strings ("pustaka"). Treat anything non-zero as validated.
  defp parse_validasi(nil), do: 0
  defp parse_validasi(v) when is_integer(v), do: v

  defp parse_validasi(v) when is_binary(v) do
    case Integer.parse(String.trim(v)) do
      {n, _} -> n
      # "pustaka" = approved by library — treat as validated
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

  defp institution_name do
    Application.get_env(:kiroku, :institution_name, "Universitas Padjadjaran")
  end

  defp parse_opts(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [batch_size: :integer, dry_run: :boolean, view: :string]
      )

    opts
  end
end
