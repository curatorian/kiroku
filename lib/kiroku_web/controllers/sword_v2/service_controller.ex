defmodule KirokuWeb.SwordV2.ServiceController do
  @moduledoc """
  SWORD v2 Service Document endpoint.

  Returns an Atom Publishing Protocol Service Document listing all
  communities (as workspaces) and their collections (as Col-IRIs that
  deposit clients POST to).
  """

  use KirokuWeb, :controller

  alias Kiroku.Repository
  alias Kiroku.Sword.Builder

  def service_document(conn, _params) do
    workspaces = Repository.list_communities_with_collections(scope: :staff)

    xml = Builder.service_document(workspaces)

    conn
    |> put_resp_content_type("application/atomserv+xml")
    |> send_resp(200, xml)
  end
end
