defmodule Mix.Tasks.Kiroku.ImportFromMssql do
  use Mix.Task

  @shortdoc "Import legacy thesis records from MSSQL into Kiroku PostgreSQL"

  @moduledoc """
  Reads all records from tbtMhsUploadThesis in the legacy MSSQL database and
  upserts them into the Kiroku PostgreSQL database.

  LegacyRepo is started manually — it is NOT in the application supervision tree.
  This task is idempotent: re-running upserts on handle.

  Usage:
      mix kiroku.import_from_mssql
      mix kiroku.import_from_mssql --dry-run
      mix kiroku.import_from_mssql --batch-size 500
      mix kiroku.import_from_mssql --collection-id <uuid>

  Options:
    --dry-run         Parse and validate but do not persist.
    --batch-size N    Stream records in batches of N (default 100).
    --collection-id   UUID of the target Collection for imported items.
  """

  import Ecto.Query
  require Logger

  alias Kiroku.{Repo, Content}
  alias Kiroku.LegacyRepo
  alias Kiroku.LegacyThesis
  alias Kiroku.Repository
  alias Kiroku.Repository.ItemKeyword

  @requirements ["app.start"]

  def run(args) do
    opts = parse_opts(args)
    batch_size = Keyword.get(opts, :batch_size, 100)
    dry_run? = Keyword.get(opts, :dry_run, false)
    collection_id = Keyword.get(opts, :collection_id)

    Mix.shell().info("Starting LegacyRepo…")

    case LegacyRepo.start_link() do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
      {:error, reason} -> Mix.raise("Cannot start LegacyRepo: #{inspect(reason)}")
    end

    if dry_run?, do: Mix.shell().info("[DRY RUN] — no database writes will occur")

    total =
      LegacyRepo.aggregate(LegacyThesis, :count, :IDControl)

    Mix.shell().info("Found #{total} legacy theses to import.")

    acc = %{inserted: 0, updated: 0, skipped: 0, errors: 0}

    result =
      LegacyRepo.transaction(
        fn ->
          from(t in LegacyThesis, order_by: fragment("IDControl"))
          |> LegacyRepo.stream(max_rows: batch_size)
          |> Enum.reduce(acc, fn record, inner_acc ->
            case import_record(record, dry_run?, collection_id) do
              {:ok, :inserted} -> Map.update!(inner_acc, :inserted, &(&1 + 1))
              {:ok, :skipped} -> Map.update!(inner_acc, :skipped, &(&1 + 1))
              {:error, _} -> Map.update!(inner_acc, :errors, &(&1 + 1))
            end
          end)
        end,
        timeout: :infinity
      )

    case result do
      {:ok, stats} ->
        Mix.shell().info("""
        Import complete.
          Inserted:  #{stats.inserted}
          Skipped:   #{stats.skipped}
          Errors:    #{stats.errors}
        """)

      {:error, reason} ->
        Mix.shell().error("Import failed: #{inspect(reason)}")
    end
  end

  defp import_record(record, dry_run?, collection_id) do
    attrs = build_item_attrs(record, collection_id)
    title = attrs[:title]

    cond do
      is_nil(title) or String.trim(title || "") == "" ->
        {:ok, :skipped}

      dry_run? ->
        id_control = Map.get(record, :IDControl)
        Mix.shell().info("  [DRY RUN] #{title} (IDControl=#{id_control})")
        {:ok, :skipped}

      true ->
        case Repository.import_item(attrs) do
          {:ok, item} ->
            create_bitstreams_for_record(item, record)
            create_keywords_for_record(item, record)
            {:ok, :inserted}

          {:error, changeset} ->
            id_control = Map.get(record, :IDControl)
            Logger.warning("Import failed IDControl=#{id_control}: #{inspect(changeset.errors)}")

            {:error, changeset}
        end
    end
  end

  defp build_item_attrs(r, collection_id) do
    judul_bersih = Map.get(r, :JudulBersih)
    judul = Map.get(r, :Judul)
    abstrak_bersih = Map.get(r, :AbstrakBersih)
    abstrak = Map.get(r, :Abstrak)
    st_publikasi = Map.get(r, :stPublikasi)
    verifikasi = Map.get(r, :Verifikasi)
    validasi = Map.get(r, :Validasi)
    idpustaka = Map.get(r, :idpustaka)
    id_control = Map.get(r, :IDControl)
    bahasa = Map.get(r, :Bahasa)
    mhs_npm = Map.get(r, :MhsNPM)
    upload_tgl = Map.get(r, :UploadTgl)
    tag_pustaka = Map.get(r, :TagPustaka)
    embargo_date = Map.get(r, :EmbargoDate)
    link_path = Map.get(r, :LinkPath)

    title = prefer_clean(judul_bersih, judul)
    abstract = prefer_clean(abstrak_bersih, abstrak)
    status = map_status(st_publikasi, verifikasi, validasi)
    handle = build_handle(idpustaka, id_control)

    %{
      handle: handle,
      idpustaka: idpustaka,
      title: title,
      abstract: abstract,
      language: map_language(bahasa),
      student_id: mhs_npm,
      date_submitted: date_from_datetime(upload_tgl),
      subject_classification: tag_pustaka,
      item_type: :skripsi,
      status: status,
      discoverable: status == :published,
      access_level: :open,
      embargo_open_date: embargo_date,
      base_url: link_path,
      institution: institution_name(),
      collection_id: collection_id
    }
  end

  defp create_bitstreams_for_record(item, r) do
    link_path = Map.get(r, :LinkPath)

    file_map = [
      {Map.get(r, :FileCover), :THUMBNAIL, 1, :open},
      {Map.get(r, :FileAbstrak), :ORIGINAL, 1, :inherit},
      {Map.get(r, :FileFullText), :ORIGINAL, 2, :inherit},
      {Map.get(r, :FileBab1), :CHAPTER, 1, :inherit},
      {Map.get(r, :FileBab2), :CHAPTER, 2, :inherit},
      {Map.get(r, :FileBab3), :CHAPTER, 3, :inherit},
      {Map.get(r, :FileBab4), :CHAPTER, 4, :inherit},
      {Map.get(r, :FileBab5), :CHAPTER, 5, :inherit},
      {Map.get(r, :FileBab6), :CHAPTER, 6, :inherit},
      {Map.get(r, :FileDaftarIsi), :SUPPLEMENTAL, 1, :inherit},
      {Map.get(r, :FilePustaka), :SUPPLEMENTAL, 2, :inherit},
      {Map.get(r, :FileLampiran), :SUPPLEMENTAL, 3, :inherit},
      {Map.get(r, :FilePresentasi), :SUPPLEMENTAL, 4, :inherit},
      {Map.get(r, :FilePengesahan), :ADMINISTRATIVE, 1, :restricted},
      {Map.get(r, :FileSurat), :ADMINISTRATIVE, 2, :restricted},
      {Map.get(r, :FileSuratIsi), :ADMINISTRATIVE, 3, :restricted}
    ]

    Enum.each(file_map, fn {file_col, bundle, seq, access} ->
      if not is_nil(file_col) and file_col != "" do
        full_url = build_file_url(link_path, file_col)

        attrs = %{
          item_id: item.id,
          filename: Path.basename(file_col),
          bundle_name: bundle,
          sequence: seq,
          description: legacy_file_description(bundle, seq),
          storage_type: :url,
          storage_url: full_url,
          access_level: access,
          embargo_open_date: item.embargo_open_date
        }

        case Content.create_bitstream(attrs) do
          {:ok, _} ->
            :ok

          {:error, reason} ->
            Logger.warning(
              "Bitstream failed item #{item.id} #{bundle}/#{seq}: #{inspect(reason)}"
            )
        end
      end
    end)
  end

  defp create_keywords_for_record(item, r) do
    parse_keywords(Map.get(r, :Keywords))
    |> Enum.with_index(0)
    |> Enum.each(fn {kw, idx} ->
      Repo.insert!(
        %ItemKeyword{
          item_id: item.id,
          keyword: kw,
          language: :id,
          position: idx
        },
        on_conflict: :nothing
      )
    end)
  end

  # ── Helpers ───────────────────────────────────────────────────────────────

  defp prefer_clean(nil, fallback), do: fallback
  defp prefer_clean("", fallback), do: fallback
  defp prefer_clean(clean, _), do: clean

  defp build_file_url(nil, file_col), do: file_col
  defp build_file_url("", file_col), do: file_col

  defp build_file_url(base, file_col) do
    base = String.trim_trailing(base, "/")
    file = String.trim_leading(file_col, "/")
    "#{base}/#{file}"
  end

  defp date_from_datetime(nil), do: nil
  defp date_from_datetime(dt), do: DateTime.to_date(dt)

  defp map_language("Indonesia"), do: :id
  defp map_language("Indonesian"), do: :id
  defp map_language("English"), do: :en
  defp map_language("Inggris"), do: :en
  defp map_language(_), do: :id

  defp map_status(1, 1, 1), do: :published
  defp map_status(1, 1, _), do: :under_review
  defp map_status(1, _, _), do: :submitted
  defp map_status(_, _, _), do: :submitted

  defp build_handle(nil, id), do: "123456789/legacy-#{id}"
  defp build_handle("", id), do: "123456789/legacy-#{id}"
  defp build_handle(h, _), do: h

  defp parse_keywords(nil), do: []
  defp parse_keywords(""), do: []

  defp parse_keywords(raw) do
    raw
    |> String.split(~r/[;,]/)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.take(10)
  end

  defp legacy_file_description(:THUMBNAIL, _), do: "Cover image"
  defp legacy_file_description(:ORIGINAL, 1), do: "Abstract"
  defp legacy_file_description(:ORIGINAL, _), do: "Full text"
  defp legacy_file_description(:CHAPTER, seq), do: "Bab #{seq}"
  defp legacy_file_description(:SUPPLEMENTAL, 1), do: "Daftar isi"
  defp legacy_file_description(:SUPPLEMENTAL, 2), do: "Daftar pustaka"
  defp legacy_file_description(:SUPPLEMENTAL, 3), do: "Lampiran"
  defp legacy_file_description(:SUPPLEMENTAL, 4), do: "Presentasi sidang"
  defp legacy_file_description(:ADMINISTRATIVE, 1), do: "Lembar pengesahan"
  defp legacy_file_description(:ADMINISTRATIVE, 2), do: "Surat pengantar"
  defp legacy_file_description(:ADMINISTRATIVE, 3), do: "Surat pengantar (isi)"
  defp legacy_file_description(_, _), do: "Document"

  defp institution_name do
    Application.get_env(:kiroku, :institution_name, "Universitas")
  end

  defp parse_opts(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [batch_size: :integer, dry_run: :boolean, collection_id: :string]
      )

    opts
  end
end
