defmodule Kiroku.LegacyThesis do
  use Ecto.Schema

  @moduledoc """
  Read-only Ecto.Schema for the tbtMhsUploadThesis table in the MSSQL legacy DB.
  This schema is used only during the import Mix task. Never written to.
  Column names match the legacy MSSQL schema exactly — do not rename them.
  """

  @primary_key {:IDControl, :integer, autogenerate: false}

  schema "tbtMhsUploadThesis" do
    field :MhsNPM, :string
    field :LinkPath, :string
    field :FileCover, :string
    field :FileAbstrak, :string
    field :FileDaftarIsi, :string
    field :FileBab1, :string
    field :FileBab2, :string
    field :FileBab3, :string
    field :FileBab4, :string
    field :FileBab5, :string
    field :FileBab6, :string
    field :FileLampiran, :string
    field :FilePustaka, :string
    field :FileSurat, :string
    field :FileSuratIsi, :string
    field :FilePengesahan, :string
    field :FilePresentasi, :string
    field :FileFullText, :string
    field :Judul, :string
    field :Abstrak, :string
    field :Bahasa, :string
    field :Keywords, :string
    field :UploadTgl, :utc_datetime
    field :idpustaka, :string
    field :TagPustaka, :string
    field :stPublikasi, :integer
    field :Verifikasi, :integer
    field :Validasi, :integer
    field :JudulBersih, :string
    field :AbstrakBersih, :string
    field :EmbargoDate, :date
  end
end
