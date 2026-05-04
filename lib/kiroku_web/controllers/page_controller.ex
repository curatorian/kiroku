defmodule KirokuWeb.PageController do
  use KirokuWeb, :controller

  alias Kiroku.Repository

  def home(conn, _params) do
    communities = Repository.list_communities()
    recent_items = Repository.list_published_items(per_page: 5)

    render(conn, :home,
      communities: communities,
      recent_items: recent_items,
      current_user: conn.assigns[:current_user]
    )
  end
end
