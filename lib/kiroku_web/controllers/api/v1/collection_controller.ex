defmodule KirokuWeb.Api.V1.CollectionController do
  @moduledoc """
  REST API v1 — Collections.

  GET  /api/v1/collections           — list all active collections
  GET  /api/v1/collections/:id       — show a single collection with item count
  POST /api/v1/collections           — create a collection (admin only)
  """

  use KirokuWeb, :controller

  import KirokuWeb.Api.ErrorHelpers

  alias Kiroku.{Repository, Repo}
  alias Kiroku.Access.Authorization
  alias Kiroku.Repository.Collection

  action_fallback KirokuWeb.FallbackController

  def index(conn, params) do
    community_id = params["community_id"]
    scope = Authorization.visibility_scope(conn.assigns[:current_user])

    if community_id do
      collections = Repository.list_collections_for_community(community_id, scope: scope)
      counts = Repository.collection_item_counts(scope: scope)

      conn
      |> put_resp_header("x-total-count", Integer.to_string(length(collections)))
      |> json(%{
        data: Enum.map(collections, &collection_json(&1, item_count: Map.get(counts, &1.id, 0)))
      })
    else
      revision = Repository.collections_revision(scope)

      KirokuWeb.Api.ETagHelpers.respond(conn, revision, fn conn ->
        collections = Repository.list_collections(scope: scope)
        counts = Repository.collection_item_counts(scope: scope)

        conn
        |> put_resp_header("x-total-count", Integer.to_string(length(collections)))
        |> json(%{
          data: Enum.map(collections, &collection_json(&1, item_count: Map.get(counts, &1.id, 0)))
        })
      end)
    end
  end

  def show(conn, %{"id" => id}) do
    case Repository.get_collection(id) do
      nil ->
        not_found(conn, "Collection not found")

      collection ->
        if Authorization.can?(conn.assigns[:current_user], :read, collection) do
          scope = Authorization.visibility_scope(conn.assigns[:current_user])
          collection = Repo.preload(collection, :community)
          item_count = Repository.count_items_for_collection(collection.id, scope: scope)

          json(conn, %{
            data: collection_json(collection, item_count: item_count, include_community: true)
          })
        else
          not_found(conn, "Collection not found")
        end
    end
  end

  def create(conn, %{"collection" => collection_params}) do
    user = conn.assigns[:current_user]

    if Authorization.can?(user, :create, %Collection{}) do
      case Repository.create_collection(collection_params) do
        {:ok, collection} ->
          conn
          |> put_status(:created)
          |> put_resp_header("location", "/api/v1/collections/#{collection.id}")
          |> json(%{data: collection_json(collection)})

        {:error, changeset} ->
          unprocessable(conn, changeset)
      end
    else
      forbidden(conn)
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
