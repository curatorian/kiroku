defmodule KirokuWeb.HandleController do
  @moduledoc """
  Resolves DSpace-style handles (e.g. 123456789/123) to the appropriate
  community, collection, or item and redirects.
  """

  use KirokuWeb, :controller

  def resolve(conn, %{"prefix" => prefix, "suffix" => suffix}) do
    handle = "#{prefix}/#{suffix}"

    conn
    |> put_flash(:error, "Handle #{handle} not found.")
    |> redirect(to: ~p"/")
  end

  def resolve_root(conn, %{"prefix" => prefix}) do
    conn
    |> put_flash(:error, "Handle #{prefix} not found.")
    |> redirect(to: ~p"/")
  end

  def statistics(conn, %{"prefix" => prefix, "suffix" => suffix}) do
    handle = "#{prefix}/#{suffix}"

    conn
    |> put_flash(:error, "Statistics for handle #{handle} not yet available.")
    |> redirect(to: ~p"/")
  end
end
