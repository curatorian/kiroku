defmodule KirokuWeb.ItemController do
  use KirokuWeb, :controller

  alias Kiroku.Repository
  alias Kiroku.Content
  alias Kiroku.Access.Authorization

  def show(conn, %{"handle" => handle}) do
    item = Repository.get_item_with_preloads!(handle)

    unless Authorization.can?(conn.assigns[:current_user], :read, item) do
      raise Phoenix.Router.NoRouteError, conn: conn, router: KirokuWeb.Router
    end

    bitstreams = Content.list_bitstreams_for_item(item.id)

    render(conn, :show, item: item, bitstreams: bitstreams)
  end
end
