defmodule KirokuWeb.SafController do
  @moduledoc """
  Serves exported SAF zip archives to staff.

  Files are produced by `Kiroku.Workers.SafExportWorker` and stored under
  `Kiroku.Saf.exports_dir/0`, keyed by Oban job id. Access is restricted to
  admins and superadmins.
  """
  use KirokuWeb, :controller

  alias Kiroku.Saf

  def download(conn, %{"job_id" => job_id}) do
    user = conn.assigns[:current_user]

    if staff?(user) do
      path = Saf.export_path(job_id)

      if File.exists?(path) do
        filename = "kiroku-saf-#{job_id}.zip"

        conn
        |> put_resp_content_type("application/zip")
        |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
        |> send_file(200, path)
      else
        conn
        |> put_status(:not_found)
        |> put_view(KirokuWeb.ErrorHTML)
        |> render(:"404")
      end
    else
      conn
      |> put_status(:forbidden)
      |> put_view(KirokuWeb.ErrorHTML)
      |> render(:"403")
    end
  end

  defp staff?(%{user_type: type}) when type in [:admin, :superadmin], do: true
  defp staff?(_), do: false
end
