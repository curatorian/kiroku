defmodule KirokuWeb.Api.V1.CommunityController do
  @moduledoc """
  REST API v1 — Communities.

  GET /api/v1/communities       — list active communities
  GET /api/v1/communities/:id   — show a single community
  """

  use KirokuWeb, :controller

  alias Kiroku.{Repository, Repo}
  alias Kiroku.Access.Authorization

  action_fallback KirokuWeb.FallbackController

  def index(conn, _params) do
    scope = Authorization.visibility_scope(conn.assigns[:current_user])
    communities = Repository.list_communities(scope: scope)
    json(conn, %{data: Enum.map(communities, &community_json/1)})
  end

  def show(conn, %{"id" => id}) do
    case Repository.get_community(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Community not found"})

      community ->
        if Authorization.can?(conn.assigns[:current_user], :read, community) do
          scope = Authorization.visibility_scope(conn.assigns[:current_user])
          community = Repo.preload(community, :collections)
          json(conn, %{data: community_json(community, include_collections: true, scope: scope)})
        else
          conn
          |> put_status(:not_found)
          |> json(%{error: "Community not found"})
        end
    end
  end

  defp community_json(community, opts \\ []) do
    base = %{
      id: community.id,
      name: community.name,
      handle: community.handle,
      short_description: community.short_description,
      description: community.description,
      position: community.position,
      inserted_at: community.inserted_at
    }

    if Keyword.get(opts, :include_collections) && Ecto.assoc_loaded?(community.collections) do
      scope = Keyword.get(opts, :scope, :public)
      levels = Authorization.visible_access_levels(scope)

      collections =
        community.collections
        |> Enum.filter(fn c -> c.is_active and c.access_level in levels end)
        |> Enum.map(&collection_brief/1)

      Map.put(base, :collections, collections)
    else
      base
    end
  end

  defp collection_brief(collection) do
    %{
      id: collection.id,
      name: collection.name,
      handle: collection.handle,
      short_description: collection.short_description
    }
  end
end
