defmodule KirokuWeb.Api.V1.CommunityController do
  @moduledoc """
  REST API v1 — Communities.

  GET  /api/v1/communities       — list active communities
  GET  /api/v1/communities/:id   — show a single community
  POST /api/v1/communities       — create a community (superadmin only)
  """

  use KirokuWeb, :controller

  import KirokuWeb.Api.ErrorHelpers

  alias Kiroku.{Repository, Repo}
  alias Kiroku.Access.Authorization
  alias Kiroku.Repository.Community

  action_fallback KirokuWeb.FallbackController

  def index(conn, _params) do
    scope = Authorization.visibility_scope(conn.assigns[:current_user])
    revision = Kiroku.Repository.communities_revision(scope)

    KirokuWeb.Api.ETagHelpers.respond(conn, revision, fn conn ->
      communities = Kiroku.Repository.list_communities(scope: scope)

      counts = Kiroku.Repository.community_item_counts(scope: scope)

      conn
      |> put_resp_header("x-total-count", Integer.to_string(length(communities)))
      |> json(%{
        data: Enum.map(communities, &community_json(&1, item_count: Map.get(counts, &1.id, 0)))
      })
    end)
  end

  @doc """
  GET /api/v1/communities/:id/subcommunities — direct children of a community
  (accepts UUID or handle).
  """
  def index_subcommunities(conn, %{"community_id" => community_id}) do
    scope = Authorization.visibility_scope(conn.assigns[:current_user])

    case resolve_community(community_id) do
      nil ->
        not_found(conn, "Community not found")

      parent ->
        children =
          Repository.list_subcommunities(parent.id, scope: scope)
          |> Enum.filter(&Authorization.can?(conn.assigns[:current_user], :read, &1))

        counts = Repository.community_item_counts(scope: scope)

        conn
        |> put_resp_header("x-total-count", Integer.to_string(length(children)))
        |> json(%{
          data: Enum.map(children, &community_json(&1, item_count: Map.get(counts, &1.id, 0)))
        })
    end
  end

  defp resolve_community(id_or_handle) do
    case Ecto.UUID.cast(id_or_handle) do
      {:ok, uuid} -> Repository.get_community(uuid)
      :error -> Repository.get_community_by_handle(id_or_handle)
    end
  end

  def show(conn, %{"id" => id}) do
    case Repository.get_community(id) do
      nil ->
        not_found(conn, "Community not found")

      community ->
        if Authorization.can?(conn.assigns[:current_user], :read, community) do
          scope = Authorization.visibility_scope(conn.assigns[:current_user])
          community = Repo.preload(community, :collections)
          item_count = Repository.count_items_for_community(community.id, scope: scope)

          json(conn, %{
            data:
              community_json(community,
                include_collections: true,
                scope: scope,
                item_count: item_count
              )
          })
        else
          not_found(conn, "Community not found")
        end
    end
  end

  def create(conn, %{"community" => community_params}) do
    user = conn.assigns[:current_user]

    if Authorization.can?(user, :create, %Community{}) do
      case Repository.create_community(community_params) do
        {:ok, community} ->
          conn
          |> put_status(:created)
          |> put_resp_header("location", "/api/v1/communities/#{community.id}")
          |> json(%{data: community_json(community)})

        {:error, changeset} ->
          unprocessable(conn, changeset)
      end
    else
      forbidden(conn)
    end
  end

  defp community_json(community, opts \\ []) do
    base = %{
      id: community.id,
      name: community.name,
      handle: community.handle,
      parent_community_id: community.parent_community_id,
      short_description: community.short_description,
      description: community.description,
      position: community.position,
      inserted_at: community.inserted_at,
      item_count: Keyword.get(opts, :item_count, 0)
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
