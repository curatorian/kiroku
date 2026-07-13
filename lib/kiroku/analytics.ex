defmodule Kiroku.Analytics do
  @moduledoc """
  Context module for analytics — view and download event recording, reporting,
  and bot filtering.
  """

  import Ecto.Query
  alias Kiroku.Repo
  alias Kiroku.Analytics.{ViewEvent, DownloadEvent}

  # Common crawler / library user-agents whose hits should not inflate counts.
  # Matched case-insensitively as a substring against the User-Agent header.
  @bot_fragments ~w(
    googlebot bingbot slurp duckduckbot baiduspider yandexbot
    facebookexternalhit twitterbot linkedinbot telegrambot whatsapp
    applebot petalbot semrushbot ahrefsbot mj12bot dotbot
    apache-httpclient wget curl python-requests scrapy bot/ crawler spider
  )

  # ── Bot detection ────────────────────────────────────────────────────────────

  @doc "True when the given user-agent looks like a crawler/library client."
  def bot?(nil), do: false

  def bot?(user_agent) when is_binary(user_agent) do
    down = String.downcase(user_agent)
    Enum.any?(@bot_fragments, &String.contains?(down, &1))
  end

  def bot?(_), do: false

  @doc """
  Hashes an IP (tuple or binary) into a stable, non-reversible identifier for
  per-client deduplication without storing the raw address.
  """
  def ip_hash(ip) when is_tuple(ip) do
    ip |> :erlang.tuple_to_list() |> Enum.join(".") |> ip_hash()
  end

  def ip_hash(ip) when is_binary(ip) do
    :crypto.hash(:sha256, ip) |> Base.encode16(case: :lower) |> String.slice(0, 16)
  end

  def ip_hash(_), do: nil

  # ── View events ────────────────────────────────────────────────────────────

  @doc """
  Records a page view for an item. Silently ignores errors so view recording
  never interrupts normal request handling. Skips crawler user-agents.

  Accepts an optional `user` (or nil for anonymous visitors) and `meta`
  keyword list with optional `:ip_hash`, `:user_agent`, and `:referer` keys.
  """
  def record_view(item_id, user, meta \\ [])

  def record_view(item_id, user, meta) do
    user_agent = Keyword.get(meta, :user_agent)

    if bot?(user_agent) do
      :ignored_bot
    else
      %ViewEvent{}
      |> ViewEvent.changeset(%{
        item_id: item_id,
        user_id: user && user.id,
        ip_hash: Keyword.get(meta, :ip_hash),
        user_agent: user_agent,
        referer: Keyword.get(meta, :referer)
      })
      |> Repo.insert()
      |> case do
        {:ok, _} -> :ok
        {:error, _} -> :ok
      end
    end
  end

  @doc """
  Returns the total (non-bot) view count for an item.
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

  # ── Download events ────────────────────────────────────────────────────────

  @doc """
  Records a bitstream download. Skips crawler user-agents. Silently ignores
  insert errors so download tracking never breaks file serving.
  """
  def record_download(bitstream_id, item_id, user, meta \\ [])

  def record_download(bitstream_id, item_id, user, meta) do
    user_agent = Keyword.get(meta, :user_agent)

    if bot?(user_agent) do
      :ignored_bot
    else
      %DownloadEvent{}
      |> DownloadEvent.changeset(%{
        bitstream_id: bitstream_id,
        item_id: item_id,
        user_id: user && user.id,
        ip_hash: Keyword.get(meta, :ip_hash),
        user_agent: user_agent,
        referer: Keyword.get(meta, :referer)
      })
      |> Repo.insert()
      |> case do
        {:ok, _} -> :ok
        {:error, _} -> :ok
      end
    end
  end

  @doc "Total (non-bot) downloads across all bitstreams of an item."
  def count_downloads_for_item(item_id) do
    Repo.one(
      from d in DownloadEvent,
        where: d.item_id == ^item_id,
        select: count(d.id)
    )
  end

  @doc "Total (non-bot) downloads for a single bitstream."
  def count_downloads_for_bitstream(bitstream_id) do
    Repo.one(
      from d in DownloadEvent,
        where: d.bitstream_id == ^bitstream_id,
        select: count(d.id)
    )
  end

  @doc """
  Most-downloaded item IDs and counts as `{item_id, count}` tuples, descending.
  """
  def top_downloaded_items(limit \\ 10) do
    Repo.all(
      from d in DownloadEvent,
        group_by: d.item_id,
        order_by: [desc: count(d.id)],
        limit: ^limit,
        select: {d.item_id, count(d.id)}
    )
  end

  @doc "Top-viewed published items with title + handle resolved for display."
  def top_viewed_with_items(limit \\ 5) do
    Repo.all(
      from v in ViewEvent,
        join: i in Kiroku.Repository.Item,
        on: i.id == v.item_id and i.status == :published,
        group_by: [i.id, i.title, i.handle],
        order_by: [desc: count(v.id)],
        limit: ^limit,
        select: %{id: i.id, title: i.title, handle: i.handle, views: count(v.id)}
    )
  end

  @doc "Top-downloaded published items with title + handle resolved for display."
  def top_downloaded_with_items(limit \\ 5) do
    Repo.all(
      from d in DownloadEvent,
        join: i in Kiroku.Repository.Item,
        on: i.id == d.item_id and i.status == :published,
        group_by: [i.id, i.title, i.handle],
        order_by: [desc: count(d.id)],
        limit: ^limit,
        select: %{id: i.id, title: i.title, handle: i.handle, downloads: count(d.id)}
    )
  end
end
