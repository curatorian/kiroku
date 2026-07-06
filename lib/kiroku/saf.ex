defmodule Kiroku.Saf do
  @moduledoc """
  Context facade for the DSpace Simple Archive Format import/export feature.

  Manages the on-disk location of exported zip archives (one per Oban job) so
  the dashboard can offer stable download links keyed by job id, and so old
  exports can be cleaned up periodically.
  """

  @exports_dir "priv/saf_exports"
  @imports_dir "priv/saf_imports"

  def exports_dir, do: @exports_dir
  def imports_dir, do: @imports_dir

  @doc "Path where the zip produced by export job `job_id` lives."
  def export_path(job_id) when is_binary(job_id) or is_integer(job_id),
    do: Path.join(@exports_dir, "#{job_id}.zip")

  @doc "Ensures the export/import scratch directories exist."
  def ensure_dirs! do
    File.mkdir_p!(@exports_dir)
    File.mkdir_p!(@imports_dir)
  end

  @doc """
  Lists finished export zips with their Oban job id, size, and creation time,
  newest first. Used by the dashboard to render download links.
  """
  def list_exports do
    ensure_dirs!()

    @exports_dir
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".zip"))
    |> Enum.map(fn name ->
      path = Path.join(@exports_dir, name)
      stat = File.stat!(path)

      %{
        job_id: String.replace_trailing(name, ".zip", ""),
        path: path,
        size: stat.size,
        inserted_at: stat.mtime
      }
    end)
    |> Enum.sort_by(& &1.inserted_at, {:desc, NaiveDateTime})
  end

  @doc "Removes exports older than `hours` ago. Returns the count removed."
  def cleanup_old(hours \\ 24) do
    cutoff = DateTime.utc_now() |> DateTime.add(-hours * 3600, :second)

    list_exports()
    |> Enum.filter(fn e ->
      case DateTime.from_naive(e.inserted_at, "Etc/UTC") do
        {:ok, dt} -> DateTime.compare(dt, cutoff) == :lt
        _ -> false
      end
    end)
    |> Enum.count(fn e -> File.rm(e.path) == :ok end)
  end

  @doc "Fetches the Oban.Job state for a job id (for UI polling)."
  def job_state(job_id) do
    case Kiroku.Repo.get(Oban.Job, job_id) do
      nil -> nil
      job -> %{state: job.state, error: job.errors, args: job.args}
    end
  end
end
