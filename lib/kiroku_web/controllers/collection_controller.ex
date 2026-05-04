defmodule KirokuWeb.CollectionController do
  use KirokuWeb, :controller

  alias Kiroku.Repository

  def show(conn, %{"handle" => handle}) do
    collection = Repository.get_collection_by_handle!(handle)
    collection = Kiroku.Repo.preload(collection, :community)
    items = Repository.list_items_for_collection(collection.id)
    item_count = Repository.count_items_for_collection(collection.id)

    render(conn, :show,
      collection: collection,
      items: items,
      item_count: item_count
    )
  end
end
