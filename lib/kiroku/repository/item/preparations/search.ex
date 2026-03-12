defmodule Kiroku.Repository.Item.Preparations.Search do
  use Ash.Resource.Preparation

  @impl true
  def prepare(query, _opts, _context) do
    term = Ash.Query.get_argument(query, :term)
    department = Ash.Query.get_argument(query, :department)
    faculty = Ash.Query.get_argument(query, :faculty)
    year = Ash.Query.get_argument(query, :year)
    item_type = Ash.Query.get_argument(query, :item_type)

    query
    |> filter_if(term, fn q ->
      Ash.Query.filter(
        q,
        expr(
          fragment(
            "to_tsvector('indonesian', coalesce(title,'') || ' ' || coalesce(abstract,'')) @@ plainto_tsquery(?)",
            ^term
          )
        )
      )
    end)
    |> filter_if(department, fn q -> Ash.Query.filter(q, expr(department == ^department)) end)
    |> filter_if(faculty, fn q -> Ash.Query.filter(q, expr(faculty == ^faculty)) end)
    |> filter_if(year, fn q -> Ash.Query.filter(q, expr(publication_year == ^year)) end)
    |> filter_if(item_type, fn q -> Ash.Query.filter(q, expr(item_type == ^item_type)) end)
    |> Ash.Query.filter(expr(status == :published and discoverable == true))
    |> Ash.Query.sort(desc: :published_at)
  end

  defp filter_if(query, nil, _fun), do: query
  defp filter_if(query, _value, fun), do: fun.(query)
end
