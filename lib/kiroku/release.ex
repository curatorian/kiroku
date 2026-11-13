defmodule Kiroku.Release do
  @moduledoc """
  Helpers for executing release-time tasks (migrations, rollbacks, seeds)
  without starting the endpoint or the full supervision tree.

  These are invoked by the overlay scripts shipped in the release:

      bin/migrate
      bin/seeds

  They run against the runtime configuration (config/runtime.exs), so the
  same environment variables required to boot the app — `DATABASE_URL`,
  `SECRET_KEY_BASE`, etc. — must be present when invoking them.
  """

  @app :kiroku

  @doc """
  Runs all pending migrations for every configured repo.
  """
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  @doc """
  Rolls back the given repo to a specific version.

      bin/kiroku eval "Kiroku.Release.rollback(Kiroku.Repo, 20250101000005)"
  """
  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Ensures all migrations are applied, then loads the seed script
  (`priv/repo/seeds.exs`). Safe to run repeatedly — seeds are idempotent.
  """
  def seeds do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn repo ->
          Ecto.Migrator.run(repo, :up, all: true)

          seed_script = Path.join([:code.priv_dir(@app), "repo", "seeds.exs"])

          if File.exists?(seed_script) do
            Code.eval_file(seed_script)
          end
        end)
    end
  end

  @doc """
  Imports legacy thesis records from MSSQL views.

  Accepts the same string args as `mix kiroku.import_from_mssql`:

      bin/import_from_mssql --check-connection
      bin/import_from_mssql --dry-run
      bin/import_from_mssql --dry-run --limit 20
      bin/import_from_mssql --batch-size 500
      bin/import_from_mssql --view Skripsi
      bin/import_from_mssql --incremental

  Or via eval:

      bin/kiroku eval "Kiroku.Release.import_from_mssql([\"--check-connection\"])"
  """
  def import_from_mssql(args \\ []) do
    start_app_without_web()

    # Repo (Postgres) and :db_connection / :tds are running before
    # LegacyRepo.start_link() is called inside Importer.run_import/1.
    Kiroku.Sync.Importer.run_import(args)
  end

  @doc """
  Deletes matched items together with their bitstream rows and — unlike the
  app's own delete paths — the actual storage objects in MinIO/local disk.

  Dry run by default:

      bin/kiroku eval 'Kiroku.Release.purge_content(["--title-prefix", "tmp_"])'

  With deletion:

      bin/kiroku eval 'Kiroku.Release.purge_content(["--title-prefix", "tmp_", "--execute"])'

  Orphan scan (storage objects with no DB row):

      bin/kiroku eval 'Kiroku.Release.purge_content(["--title-prefix", "tmp_", "--orphans"])'
  """
  def purge_content(args \\ []) do
    start_app_without_web()

    Kiroku.ContentPurge.run(args)
  end

  # `bin/kiroku eval` boots a second BEAM inside the running container. The
  # web endpoint must not bind port 4000 there — the live server owns it — so
  # force `server: false` before the application starts. Everything else
  # (Repo, Oban, storage) starts normally so eval code can do real work.
  defp start_app_without_web do
    load_app()

    endpoint_env = Application.get_env(@app, KirokuWeb.Endpoint, [])
    Application.put_env(@app, KirokuWeb.Endpoint, Keyword.put(endpoint_env, :server, false))

    Application.ensure_all_started(@app)
  end

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)
  defp load_app, do: Application.load(@app)
end
