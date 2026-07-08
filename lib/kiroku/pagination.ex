defmodule Kiroku.Pagination do
  @moduledoc """
  Lightweight pagination struct and helpers.

  Created via `build/3` from a total count, current page, and per-page size.
  The struct is passed to the `<.pagination>` component for rendering.
  """

  defstruct [:page, :per_page, :total_count, :total_pages]

  @doc """
  Builds a pagination struct from a total record count.

  Clamps `page` to a valid range (1..total_pages) so callers can pass
  unchecked user input safely.

  ## Examples

      iex> Pagination.build(0, 1, 20)
      %Pagination{page: 1, per_page: 20, total_count: 0, total_pages: 1}

      iex> Pagination.build(55, 3, 20)
      %Pagination{page: 3, per_page: 20, total_count: 55, total_pages: 3}

      iex> Pagination.build(55, 99, 20)
      %Pagination{page: 3, per_page: 20, total_count: 55, total_pages: 3}
  """
  def build(total_count, page, per_page \\ 20) do
    page = max(1, page)
    per_page = max(1, per_page)
    total_pages = max(1, ceil(total_count / per_page))
    page = min(page, total_pages)

    %__MODULE__{
      page: page,
      per_page: per_page,
      total_count: total_count,
      total_pages: total_pages
    }
  end

  @doc "Zero-based row offset for SQL LIMIT/OFFSET queries."
  def offset(%__MODULE__{page: page, per_page: per_page}), do: (page - 1) * per_page

  def has_prev?(%__MODULE__{page: 1}), do: false
  def has_prev?(%__MODULE__{}), do: true

  def has_next?(%__MODULE__{page: page, total_pages: total_pages}), do: page < total_pages

  @doc """
  Returns a list of page numbers (and `:ellipsis` atoms) for compact pager UI.

  For <= 7 pages, shows all. For more, shows first, last, and a window around
  the current page.

  ## Examples

      iex> Pagination.page_list(%Pagination{page: 1, total_pages: 3})
      [1, 2, 3]

      iex> Pagination.page_list(%Pagination{page: 5, total_pages: 20})
      [1, :ellipsis, 4, 5, 6, :ellipsis, 20]
  """
  def page_list(%__MODULE__{total_pages: total}) when total <= 7 do
    Enum.to_list(1..total)
  end

  def page_list(%__MODULE__{page: current, total_pages: total}) do
    cond do
      current <= 4 ->
        [1, 2, 3, 4, 5, :ellipsis, total]

      current >= total - 3 ->
        [1, :ellipsis, total - 4, total - 3, total - 2, total - 1, total]

      true ->
        [1, :ellipsis, current - 1, current, current + 1, :ellipsis, total]
    end
  end

  @doc """
  Builds a query-param map for a given page number, merging with existing
  params (e.g. filters). Removes empty values and omits page 1.
  """
  def page_params(params, page) when is_map(params) do
    params
    |> Map.put("page", page)
    |> Enum.reject(fn
      {_, nil} -> true
      {_, ""} -> true
      {"page", 1} -> true
      _ -> false
    end)
    |> Map.new()
  end
end
