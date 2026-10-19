defmodule Mix.Tasks.Kiroku.RefetchEmptyTitles do
  @moduledoc """
  Re-fetches items with "Empty Title" or null abstract from MSSQL.
  """

  use Mix.Task

  import Ecto.Query

  alias Kiroku.{Repo, LegacyRepo}
  alias Kiroku.Repository.Item
  alias Kiroku.LegacyView

  @shortdoc "Re-fetch empty titles from MSSQL"

  def run(args) do
    Mix.Task.run("app.start")
    dry_run? = "--dry-run" in args
    sample? = "--sample" in args

    if dry_run? do
      IO.puts(IO.ANSI.format([:bright, "DRY RUN — no changes will be made"]))
    end

    query =
      if sample? do
        from(i in Item,
          where: i.title == "Empty Title" or is_nil(i.abstract),
          select: [:id, :legacy_id, :title, :abstract],
          order_by: [asc: i.legacy_id],
          limit: 10
        )
      else
        from(i in Item,
          where: i.title == "Empty Title" or is_nil(i.abstract),
          select: [:id, :legacy_id, :title, :abstract],
          order_by: [asc: i.legacy_id]
        )
      end

    items = Repo.all(query)
    IO.puts("\nFound #{length(items)} items to re-fetch\n")

    if items == [] do
      IO.puts("Nothing to do.")
    else
      {time_us, results} =
        :timer.tc(fn ->
          items
          |> Enum.with_index(1)
          |> Enum.reduce(%{ok: 0, mssql_empty: 0, mssql_missing: 0, error: 0}, fn {item, idx},
                                                                                  acc ->
            result = refetch_item(item, dry_run?)

            if sample? or rem(idx, 500) == 0 do
              IO.puts("  [#{idx}] #{item.legacy_id} -> #{inspect(result)}")
            end

            Map.update(acc, result, 1, &(&1 + 1))
          end)
        end)

      IO.puts("\nDone in #{Float.round(time_us / 1_000_000, 1)}s")
      IO.puts("  Updated:       #{results[:ok] || 0}")
      IO.puts("  MSSQL empty:   #{results[:mssql_empty] || 0}")
      IO.puts("  MSSQL missing: #{results[:mssql_missing] || 0}")
      IO.puts("  Errors:        #{results[:error] || 0}")
    end
  end

  defp refetch_item(item, dry_run?) do
    case Kiroku.Sync.Importer.parse_legacy_id(item.legacy_id) do
      {nil, _npm} ->
        :error

      {view_name, npm} ->
        try do
          record =
            LegacyRepo.one!(
              from(v in {view_name, LegacyView},
                where: field(v, :NPM) == ^npm,
                limit: 1
              )
            )

          new_title = Map.get(record, :Judul)
          new_abstract = Map.get(record, :Abstrak)

          # Fallback: if view's Judul is empty, try tbtMhsUploadThesis
          new_title =
            if is_nil(new_title) or String.trim(to_string(new_title)) == "" do
              fallback = fetch_fallback_title(npm)
              if fallback, do: fallback, else: new_title
            else
              new_title
            end

          cond do
            is_nil(new_title) or String.trim(to_string(new_title)) == "" ->
              :mssql_empty

            true ->
              unless dry_run? do
                item
                |> Ecto.Changeset.change(title: new_title, abstract: new_abstract)
                |> Repo.update!()
              end

              :ok
          end
        rescue
          Ecto.NoResultsError -> :mssql_missing
          _ -> :error
        end
    end
  end

  defp fetch_fallback_title(npm) do
    case LegacyRepo.query!("SELECT TOP 1 Judul FROM tbtMhsUploadThesis WHERE NPM = '#{npm}'", []) do
      %{rows: [[title]]} -> title
      _ -> nil
    end
  rescue
    _ -> nil
  end
end
