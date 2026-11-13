defmodule KirokuWeb.ItemLiveReaderTest do
  use KirokuWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Kiroku.{Repository, Repo}
  alias Kiroku.Content.Bitstream

  setup do
    {:ok, community} =
      Repository.create_community(%{
        "name" => "C",
        "handle" => "reader-#{System.unique_integer([:positive])}"
      })

    {:ok, collection} =
      Repository.create_collection(%{
        "name" => "Coll",
        "community_id" => community.id,
        "handle" => "reader-coll-#{System.unique_integer([:positive])}"
      })

    {:ok, item} =
      Repository.create_item(%{
        "title" => "Reader Test Item",
        "collection_id" => collection.id,
        "status" => "published",
        "discoverable" => true,
        "handle" => "reader-item-#{System.unique_integer([:positive])}"
      })

    {:ok, pdf} =
      %Bitstream{}
      |> Bitstream.changeset(%{
        "item_id" => item.id,
        "filename" => "thesis.pdf",
        "bundle_name" => "ORIGINAL",
        "mime_type" => "application/pdf",
        "storage_type" => "local",
        "storage_path" => "items/#{item.id}/ORIGINAL/#{System.unique_integer([:positive])}.pdf"
      })
      |> Repo.insert()

    {:ok, image} =
      %Bitstream{}
      |> Bitstream.changeset(%{
        "item_id" => item.id,
        "filename" => "figure.png",
        "bundle_name" => "SUPPLEMENTAL",
        "mime_type" => "image/png",
        "storage_type" => "local",
        "storage_path" =>
          "items/#{item.id}/SUPPLEMENTAL/#{System.unique_integer([:positive])}.png"
      })
      |> Repo.insert()

    %{item: item, pdf: pdf, image: image}
  end

  test "PDF files open in the modal reader instead of a direct link", %{
    conn: conn,
    item: item,
    pdf: pdf
  } do
    {:ok, view, html} = live(conn, ~p"/items/#{item.handle}")

    # No direct link for the PDF — its URL is not exposed.
    refute html =~ ~s(href="/items/#{item.handle}/bitstreams/#{pdf.id}")

    view
    |> element("button[phx-click='read_file'][phx-value-id='#{pdf.id}']")
    |> render_click()

    assert has_element?(view, "#pdf-reader")
    assert has_element?(view, "#close-pdf-reader")

    reader = element(view, "#pdf-reader")
    assert render(reader) =~ data_bitstream_id_attr(pdf.id)
  end

  test "the original filename is never rendered on the page", %{
    conn: conn,
    item: item,
    pdf: pdf
  } do
    {:ok, view, html} = live(conn, ~p"/items/#{item.handle}")

    # Filenames often carry student identifiers (NPM, names) — the sidebar and
    # the reader must show the description (or a generic label) instead.
    refute html =~ pdf.filename

    view
    |> element("button[phx-click='read_file'][phx-value-id='#{pdf.id}']")
    |> render_click()

    rendered = render(view)
    refute rendered =~ pdf.filename
    assert rendered =~ "Document"
  end

  test "non-PDF files keep the direct download link", %{conn: conn, item: item, image: image} do
    {:ok, view, html} = live(conn, ~p"/items/#{item.handle}")

    assert html =~ ~s(href="/items/#{item.handle}/bitstreams/#{image.id}")
    refute has_element?(view, "button[phx-click='read_file'][phx-value-id='#{image.id}']")
  end

  test "closing the reader removes the modal", %{conn: conn, item: item, pdf: pdf} do
    {:ok, view, _html} = live(conn, ~p"/items/#{item.handle}")

    view
    |> element("button[phx-click='read_file'][phx-value-id='#{pdf.id}']")
    |> render_click()

    assert has_element?(view, "#pdf-reader")

    view |> element("#close-pdf-reader") |> render_click()

    refute has_element?(view, "#pdf-reader")
  end

  test "non-PDF files are rejected by the read_file event", %{
    conn: conn,
    item: item,
    image: image
  } do
    {:ok, view, _html} = live(conn, ~p"/items/#{item.handle}")

    render_click(view, "read_file", %{"id" => image.id})

    refute has_element?(view, "#pdf-reader")
  end

  defp data_bitstream_id_attr(id), do: ~s(data-bitstream-id="#{id}")
end
