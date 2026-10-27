defmodule Kiroku.Repo.Migrations.AddTokenTypeAndApprovedAtToApiTokens do
  use Ecto.Migration

  def change do
    alter table(:api_tokens) do
      add :token_type, :text, null: false, default: "user"
      add :approved_at, :utc_datetime_usec
    end

    execute(
      "ALTER TABLE api_tokens ADD CONSTRAINT api_tokens_token_type_check CHECK (token_type IN ('user', 'device'))",
      "ALTER TABLE api_tokens DROP CONSTRAINT api_tokens_token_type_check"
    )
  end
end
