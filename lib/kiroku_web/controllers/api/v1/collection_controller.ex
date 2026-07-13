defmodule KirokuWeb.Api.V1.CollectionController do
  @moduledoc """
  REST API v1 — Collections.

  GET /api/v1/collections           — list all active collections
  GET /api/v1/collections/:id       — show a single collection with item count
  """

  use KirokuWeb, :controller

  alias Kiroku.{Repository, Repo}
  alias Kiroku.Access.Authorization

  def index(conn, params) do
    community_id = params["community_id"]
    scope = Authorization.visibility_scope(conn.assigns[:current_user])

    collections =
      if community_id do
        Repository.list_collections_for_community(community_id, scope: scope)
      else
        Repository.list_collections(scope: scope)
      end

    json(conn, %{data: Enum.map(collections, &collection_json/1)})
  end

  def show(conn, %{"id" => id}) do
    case Repository.get_collection(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Collection not found"})

      collection ->
        if Authorization.can?(conn.assigns[:current_user], :read, collection) do
          scope = Authorization.visibility_scope(conn.assigns[:current_user])
          collection = Repo.preload(collection, :community)
          item_count = Repository.count_items_for_collection(collection.id, scope: scope)

          json(conn, %{
            data: collection_json(collection, item_count: item_count, include_community: true)
          })
        else
          conn
          |> put_status(:not_found)
          |> json(%{error: "Collection not found"})
        end
    end
  end

  defp collection_json(collection, opts \\ []) do
    base = %{
      id: collection.id,
      name: collection.name,
      handle: collection.handle,
      short_description: collection.short_description,
      community_id: collection.community_id,
      position: collection.position,
      inserted_at: collection.inserted_at
    }

    base =
      if Keyword.get(opts, :item_count) do
        Map.put(base, :item_count, opts[:item_count])
      else
        base
      end

    if Keyword.get(opts, :include_community) && Ecto.assoc_loaded?(collection.community) &&
         collection.community do
      Map.put(base, :community, %{
        id: collection.community.id,
        name: collection.community.name,
        handle: collection.community.handle
      })
    else
      base
    end
  end
end
