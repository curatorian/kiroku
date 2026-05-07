defmodule KirokuWeb.HandleController do
  @moduledoc """
  DSpace handle resolver. Provides backwards-compatible `/handle/prefix/suffix`
  URLs that redirect to the appropriate Kiroku resource.

  This mirrors the DSpace 7 handle resolution pattern so that existing external
  links and citations pointing to the old repository continue to work.
  """

  use KirokuWeb, :controller

  alias Kiroku.{Repo, Repository}
  alias Kiroku.Repository.{Community, Collection}

  def show(conn, %{"path" => path_parts}) do
    handle = Enum.join(path_parts, "/")

    cond do
      item = Repository.get_item_by_handle(handle) ->
        redirect(conn, to: ~p"/items/#{item.handle}")

      community = Repo.get_by(Community, handle: handle) ->
        redirect(conn, to: ~p"/communities/#{community.handle}")

      collection = Repo.get_by(Collection, handle: handle) ->
        redirect(conn, to: ~p"/collections/#{collection.handle}")

      true ->
        conn
        |> put_status(:not_found)
        |> put_view(KirokuWeb.ErrorHTML)
        |> render(:"404")
    end
  end
end
