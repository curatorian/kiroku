defmodule KirokuWeb.PageController do
  use KirokuWeb, :controller

  import Ecto.Query
  alias Kiroku.Repository
  alias Kiroku.Access.Authorization
  alias Kiroku.Repository.Community
  alias Kiroku.Repo
  alias KirokuWeb.SEO

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
    brand = Kiroku.Settings.brand_settings()

    conn
    |> assign(:page_title, brand.name)
    |> SEO.put_page_seo(path: ~p"/", description: brand.description)
    |> render(:home,
      communities: communities,
      recent_items: recent_items,
      current_user: conn.assigns[:current_user],
      brand: brand
    )
  end

  def api_info(conn, _params) do
    brand = Kiroku.Settings.brand_settings()

    conn
    |> assign(:page_title, "Developer & API Access")
    |> SEO.put_page_seo(path: ~p"/api-info", description: brand.description)
    |> render(:api_info,
      current_user: conn.assigns[:current_user],
      brand: brand
    )
  end
end
