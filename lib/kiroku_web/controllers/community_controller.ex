defmodule KirokuWeb.CommunityController do
  use KirokuWeb, :controller

  alias Kiroku.Repository

  def index(conn, _params) do
    communities = Repository.list_communities()
    render(conn, :index, communities: communities)
  end

  def show(conn, %{"handle" => handle}) do
    community = Repository.get_community_by_handle!(handle)
    community = Kiroku.Repo.preload(community, :collections)
    render(conn, :show, community: community)
  end
end
