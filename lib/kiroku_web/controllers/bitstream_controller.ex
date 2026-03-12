defmodule KirokuWeb.BitstreamController do
  @moduledoc """
  Serves bitstream file downloads with access control.
  """

  use KirokuWeb, :controller

  def download_by_handle_filename(conn, %{
        "prefix" => _prefix,
        "suffix" => _suffix,
        "filename" => _filename
      }) do
    conn
    |> put_status(:not_implemented)
    |> text("Bitstream download not yet implemented")
  end

  def download_by_handle(conn, %{
        "prefix" => _prefix,
        "suffix" => _suffix,
        "sequence" => _sequence,
        "filename" => _filename
      }) do
    conn
    |> put_status(:not_implemented)
    |> text("Bitstream download not yet implemented")
  end

  def download(conn, %{"id" => _id}) do
    conn
    |> put_status(:not_implemented)
    |> text("Bitstream download not yet implemented")
  end
end
