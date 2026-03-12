defmodule KirokuWeb.CitationController do
  @moduledoc """
  Exports item metadata as citation files (BibTeX, RIS, EndNote).
  """

  use KirokuWeb, :controller

  def bibtex(conn, %{"id" => _id}) do
    conn
    |> put_resp_content_type("application/x-bibtex")
    |> send_resp(:not_implemented, "BibTeX export not yet implemented")
  end

  def ris(conn, %{"id" => _id}) do
    conn
    |> put_resp_content_type("application/x-research-info-systems")
    |> send_resp(:not_implemented, "RIS export not yet implemented")
  end

  def endnote(conn, %{"id" => _id}) do
    conn
    |> put_resp_content_type("application/x-endnote-refer")
    |> send_resp(:not_implemented, "EndNote export not yet implemented")
  end
end
