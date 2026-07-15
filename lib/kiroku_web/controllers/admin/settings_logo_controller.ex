defmodule KirokuWeb.Admin.SettingsLogoController do
  use KirokuWeb, :controller

  alias Kiroku.{Settings, Storage.Uploader}

  @allowed_exts ~w(.png .jpg .jpeg .svg .ico .webp)

  # Plain multipart POST — no LiveView websocket involved, so it works
  # regardless of upload-hook state.
  def upload(conn, %{"logo" => %Plug.Upload{filename: filename} = upload})
      when is_binary(filename) and filename != "" do
    ext = filename |> Path.extname() |> String.downcase()

    if ext in @allowed_exts do
      key = "brand/logo#{ext}"

      with {:ok, content} <- File.read(upload.path),
           {:ok, _} <-
             Uploader.upload(key, content,
               mime_type: upload.content_type || "application/octet-stream"
             ) do
        Settings.put("brand_logo_url", Uploader.presign_url(Settings.storage_bucket(), key))

        conn
        |> put_flash(:info, "Logo uploaded. It's now the site logo and favicon.")
        |> redirect(to: ~p"/admin/settings")
      else
        _ ->
          conn
          |> put_flash(:error, "Logo upload failed. Please try again.")
          |> redirect(to: ~p"/admin/settings")
      end
    else
      conn
      |> put_flash(:error, "Unsupported file type. Use PNG, JPG, SVG, ICO, or WebP.")
      |> redirect(to: ~p"/admin/settings")
    end
  end

  def upload(conn, _params) do
    conn
    |> put_flash(:error, "No file selected.")
    |> redirect(to: ~p"/admin/settings")
  end

  def delete(conn, _params) do
    Settings.put("brand_logo_url", "")

    conn
    |> put_flash(:info, "Logo removed. Falling back to the default kiroku.ico.")
    |> redirect(to: ~p"/admin/settings")
  end
end
