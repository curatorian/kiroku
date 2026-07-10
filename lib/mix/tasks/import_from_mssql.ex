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
       mix kiroku.import_from_mssql --dry-run --limit 20
       mix kiroku.import_from_mssql --batch-size 500
       mix kiroku.import_from_mssql --view Skripsi     (import one view only)
       mix kiroku.import_from_mssql --incremental      (only sync changed records)
       mix kiroku.import_from_mssql --check-connection (test MSSQL connection only)

   Options:

     --dry-run         Parse and validate but do not persist. Defaults to a
                       5-record sample per view unless --limit is given.
     --limit N         Process at most N records per view (default 5 in dry-run,
                       unlimited otherwise).
     --batch-size N    Stream records in batches of N (default 100).
     --view NAME       Import only this view (Skripsi / Tesis / Disertasi / Tugas-Akhir).
     --incremental     Only sync records that have changed since last sync.
     --check-connection Test MSSQL connection and display status without importing.

  The heavy lifting lives in `Kiroku.Sync.Importer.run_import/1`, which is also
  used by the production release overlay `bin/import_from_mssql` (no Mix needed).

  **Release / container usage** (Mix is not available in releases):

       podman compose run --rm app bin/import_from_mssql --check-connection
       podman compose run --rm app bin/import_from_mssql --dry-run
       podman compose run --rm app bin/import_from_mssql --view Skripsi
  """

  @requirements ["app.start"]

  def run(args) do
    Kiroku.Sync.Importer.run_import(args)
  end
end
