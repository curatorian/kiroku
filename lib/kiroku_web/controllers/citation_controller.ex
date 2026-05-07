defmodule KirokuWeb.CitationController do
  @moduledoc """
  Serves citation downloads for repository items.

  Route: GET /citation/:id.:format
  Formats: apa, mla, chicago, ieee, bibtex, ris

  Returns plain text (or BibTeX/RIS) suitable for download or display.
  """

  use KirokuWeb, :controller

  alias Kiroku.{Repository, Export}

  @supported_formats ~w(apa mla chicago ieee bibtex ris)

  def show(conn, %{"id" => id, "format" => format}) when format in @supported_formats do
    format_atom = String.to_existing_atom(format)

    case Repository.get_item(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> put_view(KirokuWeb.ErrorHTML)
        |> render(:"404")

      item ->
        item = Kiroku.Repo.preload(item, [:item_authors, :item_keywords])

        preloads = %{
          authors: item.item_authors,
          keywords: item.item_keywords
        }

        case Export.Citation.generate(item, format_atom, preloads) do
          {:ok, citation} ->
            mime = Export.Citation.mime_type(format_atom)
            ext = Export.Citation.file_extension(format_atom)
            filename = "citation-#{item.id}.#{ext}"

            conn
            |> put_resp_content_type(mime)
            |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
            |> send_resp(200, citation)

          {:error, _reason} ->
            conn
            |> put_status(:unprocessable_entity)
            |> put_view(KirokuWeb.ErrorHTML)
            |> render(:"422")
        end
    end
  end

  def show(conn, %{"format" => format}) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      error:
        "Unsupported citation format: #{format}. Supported: #{Enum.join(@supported_formats, ", ")}"
    })
  end
end
