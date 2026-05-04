defmodule Kiroku.Repo do
  use Ecto.Repo,
    otp_app: :kiroku,
    adapter: Ecto.Adapters.Postgres
end
