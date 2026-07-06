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
       mix kiroku.import_from_mssql --incremental      (only sync changed records)
       mix kiroku.import_from_mssql --check-connection (test MSSQL connection only)

  Options:

     --dry-run         Parse and validate but do not persist.
     --batch-size N    Stream records in batches of N (default 100).
     --view NAME       Import only this view (Skripsi / Tesis / Disertasi / Tugas-Akhir).
     --incremental     Only sync records that have changed since last sync.
     --check-connection Test MSSQL connection and display status without importing.

  The heavy lifting lives in `Kiroku.Sync.Importer`. This task is a thin CLI
  wrapper; the dashboard triggers the same logic via `Kiroku.Workers.ImportWorker`.
  """

  require Logger

  alias Kiroku.{LegacyRepo, Sync}
  alias Kiroku.Sync.Importer

  @requirements ["app.start"]

  # ── Entry point ────────────────────────────────────────────────────────────

  def run(args) do
    opts = parse_opts(args)
    batch_size = Keyword.get(opts, :batch_size, 100)
    dry_run? = Keyword.get(opts, :dry_run, false)
    incremental? = Keyword.get(opts, :incremental, false)
    only_view = Keyword.get(opts, :view)
    check_connection? = Keyword.get(opts, :check_connection, false)

    if check_connection? do
      check_mssql_connection()
      System.halt(0)
    end

    Mix.shell().info("Starting LegacyRepo…")

    case LegacyRepo.start_link() do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
      {:error, reason} -> Mix.raise("Cannot start LegacyRepo: #{inspect(reason)}")
    end

    if dry_run?, do: Mix.shell().info("[DRY RUN] — no database writes will occur")
    if incremental?, do: Mix.shell().info("[INCREMENTAL] — only syncing changed records")

    views_to_run =
      case only_view do
        nil -> Importer.views()
        name -> Enum.filter(Importer.views(), fn {v, _} -> v == name end)
      end

    if views_to_run == [] do
      valid = Enum.map_join(Importer.views(), ", ", fn {v, _} -> v end)
      Mix.raise("No matching view. Valid values: #{valid}")
    end

    final_stats =
      Enum.reduce(views_to_run, %{inserted: 0, updated: 0, skipped: 0, failed: 0}, fn {view_name,
                                                                                       _},
                                                                                      acc ->
        Mix.shell().info("\n── View: #{view_name} ──")

        sync_run =
          if dry_run? do
            nil
          else
            {:ok, run} =
              Sync.start_sync_run(view_name, %{
                run_type: "import",
                triggered_by: "cli"
              })

            run
          end

        view_stats =
          Importer.run_view(view_name,
            dry_run: dry_run?,
            incremental: incremental?,
            sync_run: sync_run,
            batch_size: batch_size,
            log: true
          )

        if sync_run do
          complete_or_fail(sync_run, view_stats)
        end

        %{
          inserted: acc.inserted + view_stats.inserted,
          updated: acc.updated + view_stats.updated,
          skipped: acc.skipped + view_stats.skipped,
          failed: acc.failed + view_stats.failed
        }
      end)

    Mix.shell().info("""

    Import complete.
      Inserted : #{final_stats.inserted}
      Updated  : #{final_stats.updated}
      Skipped  : #{final_stats.skipped}
      Errors   : #{final_stats.failed}
    """)
  end

  defp complete_or_fail(sync_run, %{failed: failed, total: total})
       when failed > 0 and total > 0 and failed >= total do
    Sync.fail_sync_run(sync_run, "all #{failed} records failed")
  end

  defp complete_or_fail(sync_run, view_stats) do
    Sync.complete_sync_run(sync_run, %{
      processed: view_stats.processed,
      inserted: view_stats.inserted,
      updated: view_stats.updated,
      failed: view_stats.failed,
      last_synced_at: DateTime.utc_now(),
      last_synced_legacy_id: Importer.last_legacy_id(sync_run.source_view)
    })
  end

  defp parse_opts(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          batch_size: :integer,
          dry_run: :boolean,
          view: :string,
          incremental: :boolean,
          check_connection: :boolean
        ]
      )

    opts
  end

  def check_mssql_connection do
    Mix.shell().info("Checking MSSQL connection status…")
    Mix.shell().info("")

    config = Kiroku.LegacyRepo.Inspector.get_config()

    if !config.configured? do
      Mix.shell().error("❌ MSSQL connection is not configured.")
      Mix.shell().info("")
      Mix.shell().info("Required environment variables:")
      Mix.shell().info("  • MSSQL_HOST")
      Mix.shell().info("  • MSSQL_DB")
      Mix.shell().info("  • MSSQL_USER")
      Mix.shell().info("  • MSSQL_PASS")
      Mix.shell().info("  • MSSQL_PORT (optional, default: 1433)")
      Mix.shell().info("")
      Mix.shell().info("Please set these environment variables and try again.")
      System.halt(1)
    end

    Mix.shell().info("Connection Configuration:")
    Mix.shell().info("  • Hostname: #{config.hostname}")
    Mix.shell().info("  • Database: #{config.database}")
    Mix.shell().info("  • Port: #{config.port}")
    Mix.shell().info("  • Username: #{config.username}")
    Mix.shell().info("  • Pool Size: #{config.pool_size}")
    Mix.shell().info("")

    case Kiroku.LegacyRepo.Inspector.test_connection() do
      {:ok, info} ->
        Mix.shell().info("✅ Connection successful!")
        Mix.shell().info("  • Server Version: #{info.version}")
        Mix.shell().info("  • Connected at: #{info.connected_at}")
        Mix.shell().info("")
        Mix.shell().info("The MSSQL database is accessible and ready for import.")

      {:error, :repo_not_started} ->
        Mix.shell().error("❌ Connection failed: LegacyRepo could not be started.")
        Mix.shell().info("")
        Mix.shell().info("This may be due to:")
        Mix.shell().info("  • Network connectivity issues")
        Mix.shell().info("  • Incorrect database credentials")
        Mix.shell().info("  • Firewall blocking the connection")
        Mix.shell().info("  • MSSQL server not running")
        Mix.shell().info("")
        Mix.shell().error("Please check your configuration and try again.")
        System.halt(1)

      {:error, :connection_failed} ->
        Mix.shell().error("❌ Connection failed: Unable to reach MSSQL server.")
        Mix.shell().info("")
        Mix.shell().info("This may be due to:")
        Mix.shell().info("  • Network connectivity issues")
        Mix.shell().info("  • Incorrect database credentials")
        Mix.shell().info("  • Firewall blocking the connection")
        Mix.shell().info("  • MSSQL server not running")
        Mix.shell().info("")
        Mix.shell().error("Please check your configuration and try again.")
        System.halt(1)

      {:error, reason} ->
        Mix.shell().error("❌ Connection failed: #{inspect(reason)}")
        Mix.shell().info("")
        Mix.shell().error("Please check your configuration and try again.")
        System.halt(1)
    end
  end
end
