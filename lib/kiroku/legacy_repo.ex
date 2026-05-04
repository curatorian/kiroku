defmodule Kiroku.LegacyRepo do
  use Ecto.Repo,
    otp_app: :kiroku,
    adapter: Ecto.Adapters.Tds

  @moduledoc """
  Read-only Ecto.Repo for the MSSQL legacy database (tbtMhsUploadThesis).
  This repo is started manually in the import Mix task — it is NOT part of
  the production application supervision tree. It is never written to.
  """
end
