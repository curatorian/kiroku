defmodule KirokuWeb.SearchController do
  use KirokuWeb, :controller

  alias Kiroku.Repository

  def index(conn, params) do
    search_params = %{
      term: params["q"],
      item_type: params["type"],
      faculty: params["faculty"],
      department: params["department"],
      year: params["year"] && String.to_integer(params["year"]),
      collection_id: params["collection_id"],
      page: page_param(params["page"])
    }

    items = Repository.search_items(search_params)
    render(conn, :index, items: items, params: search_params, query: params["q"])
  end

  defp page_param(nil), do: 1

  defp page_param(p) do
    case Integer.parse(p) do
      {n, ""} when n > 0 -> n
      _ -> 1
    end
  end
end
