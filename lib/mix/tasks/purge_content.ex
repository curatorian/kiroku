defmodule Mix.Tasks.Kiroku.PurgeContent do
  @shortdoc "Delete items together with their storage objects (dry run by default)"

  @moduledoc """
  Deletes matched items together with their bitstream rows AND the actual
  storage objects (MinIO / local disk) — the app's own delete paths leave the
  files behind. Also lists orphaned storage objects with --orphans.

  Dry run by default; pass --execute to actually delete.

      mix kiroku.purge_content
      mix kiroku.purge_content --title-prefix tmp_ --since 2026-11-10T00:00:00
      mix kiroku.purge_content --item-ids <uuid>,<uuid> --title-prefix "" --execute
      mix kiroku.purge_content --orphans

  In production releases use `bin/kiroku eval 'Kiroku.Release.purge_content([...])'`.
  """

  use Mix.Task

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args), do: Kiroku.ContentPurge.run(args)
end
