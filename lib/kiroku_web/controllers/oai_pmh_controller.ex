defmodule KirokuWeb.OaiPmhController do
  @moduledoc """
  OAI-PMH 2.0 protocol endpoint for metadata harvesting.
  """

  use KirokuWeb, :controller

  def handle_request(conn, _params) do
    conn
    |> put_resp_content_type("text/xml")
    |> send_resp(
      :not_implemented,
      ~s(<?xml version="1.0" encoding="UTF-8"?><error>OAI-PMH not yet implemented</error>)
    )
  end
end
