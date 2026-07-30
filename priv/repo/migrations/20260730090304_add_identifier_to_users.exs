defmodule Kiroku.Repo.Migrations.AddIdentifierToUsers do
  use Ecto.Migration

  def change do
    execute """
            ALTER TABLE users ADD COLUMN IF NOT EXISTS identifier varchar(255)
            """,
            """
            ALTER TABLE users DROP COLUMN IF EXISTS identifier
            """

    execute """
            CREATE UNIQUE INDEX IF NOT EXISTS users_identifier_index ON users (identifier)
            """,
            """
            DROP INDEX IF EXISTS users_identifier_index
            """
  end
end
