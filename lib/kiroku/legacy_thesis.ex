defmodule Kiroku.LegacyView do
  use Ecto.Schema

  @moduledoc """
  Read-only Ecto.Schema shared across all four MSSQL legacy views:
    dbo.Skripsi, dbo.Tesis, dbo.Disertasi, dbo.Tugas-Akhir

  All views expose the same column layout. Use the dynamic source syntax
  at query time:

      from(v in {"Skripsi", Kiroku.LegacyView}, ...)
      from(v in {"Tesis",   Kiroku.LegacyView}, ...)

  This schema is used only during the import Mix task. Never written to.
  Column names match the legacy MSSQL view schema exactly.
  """

  # NPM (student number) is unique within each view
  @primary_key {:NPM, :string, autogenerate: false}

  # The default schema name is overridden per-query; this is just a placeholder
  schema "Skripsi" do
    field :Nama, :string
    field :Kode, :string
    field :Program_Studi, :string
    field :Jenjang, :string
    field :Fakultas, :string
    field :Jenis, :string
    field :Tgl_Upload, :utc_datetime
    field :LinkPath, :string
    field :FileBab1, :string
    field :FileBab2, :string
    field :FileBab3, :string
    field :FileBab4, :string
    field :FileBab5, :string
    field :FileBab6, :string
    field :FileCover, :string
    field :FileAbstrak, :string
    field :FileDaftarIsi, :string
    field :FileLampiran, :string
    field :FilePustaka, :string
    field :FileSurat, :string
    field :FileSuratIsi, :string
    field :FilePengesahan, :string
    field :Lulus, :string
    field :Verifikasi, :integer
    # Validasi is VARCHAR in legacy — may hold integers or strings like "pustaka"
    field :Validasi, :string
    field :stPublikasi, :integer
    field :TagPustaka, :string
    field :idpustaka, :string
    field :Judul, :string
    field :Abstrak, :string
  end
end
