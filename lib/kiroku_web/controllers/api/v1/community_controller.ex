defmodule KirokuWeb.Api.V1.CommunityController do
  @moduledoc """
  REST API v1 — Communities.

  GET /api/v1/communities       — list active communities
  GET /api/v1/communities/:id   — show a single community
  """

  use KirokuWeb, :controller

  alias Kiroku.{Repository, Repo}

  action_fallback KirokuWeb.FallbackController

  def index(conn, _params) do
    communities = Repository.list_communities()
    json(conn, %{data: Enum.map(communities, &community_json/1)})
  end

  def show(conn, %{"id" => id}) do
    case Repository.get_community(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Community not found"})

      community ->
        community = Repo.preload(community, :collections)
        json(conn, %{data: community_json(community, include_collections: true)})
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
      collections =
        community.collections
        |> Enum.filter(& &1.is_active)
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
