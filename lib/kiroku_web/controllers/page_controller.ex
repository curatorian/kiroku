defmodule KirokuWeb.PageController do
  use KirokuWeb, :controller

  import Ecto.Query
  alias Kiroku.Repository
  alias Kiroku.Access.Authorization
  alias Kiroku.Repository.Community
  alias Kiroku.Repo

  def home(conn, _params) do
    scope = Authorization.visibility_scope(conn.assigns[:current_user])
    levels = Authorization.visible_access_levels(scope)

    ordered_subcommunities =
      from(c in Community,
        where: c.is_active == true and c.access_level in ^levels,
        order_by: c.position
      )

    ordered_collections =
      from(c in Kiroku.Repository.Collection,
        where: c.is_active == true and c.access_level in ^levels,
        order_by: c.position
      )

    communities =
      Repo.all(
        from c in Community,
          where:
            c.is_active == true and is_nil(c.parent_community_id) and
              c.access_level in ^levels,
          order_by: c.position,
          preload: [
            subcommunities: ^{ordered_subcommunities, [collections: ordered_collections]},
            collections: ^ordered_collections
          ]
      )

    recent_items = Repository.list_published_items(per_page: 5, scope: scope)

    render(conn, :home,
      communities: communities,
      recent_items: recent_items,
      current_user: conn.assigns[:current_user],
      brand: Kiroku.Settings.brand_settings()
    )
  end

  def api_info(conn, _params) do
    render(conn, :api_info,
      current_user: conn.assigns[:current_user],
      brand: Kiroku.Settings.brand_settings()
    )
  end
end
