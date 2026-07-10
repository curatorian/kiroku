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
    load_app()

    # `bin/kiroku eval` does NOT start the application or its dependencies
    # (unlike Mix's `@requirements ["app.start"]`). We must start the full app
    # so Kiroku.Repo (Postgres) and :db_connection / :tds are running before
    # LegacyRepo.start_link() is called inside Importer.run_import/1.
    #
    # This is safe in a `podman compose run --rm` container because it gets
    # its own network namespace (no port conflict with the running app).
    Application.ensure_all_started(:kiroku)

    Kiroku.Sync.Importer.run_import(args)
  end

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)
  defp load_app, do: Application.load(@app)
end
