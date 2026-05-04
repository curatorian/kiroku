defmodule Kiroku.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :string, null: false
      add :hashed_password, :string, null: false
      add :confirmed_at, :naive_datetime

      add :user_type, :string, null: false, default: "submitter"
      add :display_name, :string
      add :student_id, :string
      add :faculty, :string
      add :department, :string
      add :avatar_url, :string

      timestamps()
    end

    create unique_index(:users, [:email])
    create index(:users, [:user_type])
  end
end
