defmodule Kiroku.Analytics do
  @moduledoc """
  Context module for analytics — view event recording and reporting.
  """

  import Ecto.Query
  alias Kiroku.Repo
  alias Kiroku.Analytics.ViewEvent

  @doc """
  Records a page view for an item. Silently ignores errors so view recording
  never interrupts normal request handling.

  Accepts an optional `user` (or nil for anonymous visitors) and `meta` keyword
  list with optional `:ip_hash`, `:user_agent`, and `:referer` keys.
  """
  def record_view(item_id, user, meta \\ []) do
    attrs = %{
      item_id: item_id,
      user_id: user && user.id,
      ip_hash: Keyword.get(meta, :ip_hash),
      user_agent: Keyword.get(meta, :user_agent),
      referer: Keyword.get(meta, :referer)
    }

    %ViewEvent{}
    |> ViewEvent.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, _} -> :ok
      {:error, _} -> :ok
    end
  end

  @doc """
  Returns the total view count for an item.
  """
  def count_views(item_id) do
    Repo.one(
      from v in ViewEvent,
        where: v.item_id == ^item_id,
        select: count(v.id)
    )
  end

  @doc """
  Returns the most-viewed published item IDs and their view counts.
  Returns a list of `{item_id, count}` tuples, ordered by count descending.
  """
  def top_viewed_items(limit \\ 10) do
    Repo.all(
      from v in ViewEvent,
        group_by: v.item_id,
        order_by: [desc: count(v.id)],
        limit: ^limit,
        select: {v.item_id, count(v.id)}
    )
  end

  @doc """
  Returns view counts grouped by date for an item (last N days).
  Returns a list of `{date, count}` tuples, ordered by date ascending.
  """
  def views_by_date(item_id, days \\ 30) do
    since = Date.add(Date.utc_today(), -days)

    Repo.all(
      from v in ViewEvent,
        where:
          v.item_id == ^item_id and
            fragment("DATE(?)", v.inserted_at) >= ^since,
        group_by: fragment("DATE(?)", v.inserted_at),
        order_by: fragment("DATE(?)", v.inserted_at),
        select: {fragment("DATE(?)", v.inserted_at), count(v.id)}
    )
  end
end
