defmodule KirokuWeb.SeoController do
  @moduledoc """
  Serves `robots.txt` and `sitemap.xml` for search-engine discovery.

  Both are controller-rendered (not static assets) so the sitemap URL embedded
  in `robots.txt` and every `<loc>` in the sitemap use the configured absolute
  base URL, and the sitemap reflects the current set of public content without
  a rebuild step.
  """

  use KirokuWeb, :controller

  alias Kiroku.Repository
  alias KirokuWeb.Endpoint

  @doc "GET /robots.txt"
  def robots(conn, _params) do
    base = Endpoint.url()

    body = """
    # Kiroku Institutional Repository — robots.txt
    User-agent: *
    Allow: /
    Disallow: /users/
    Disallow: /admin/
    Disallow: /my/
    Disallow: /api/

    Sitemap: #{base}/sitemap.xml
    """

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, body)
  end

  @doc "GET /sitemap.xml"
  def sitemap(conn, _params) do
    base = Endpoint.url()

    %{items: items, communities: communities, collections: collections} =
      Repository.sitemap_entries()

    urls =
      Enum.map(communities, &entry(base, "/communities/#{&1.handle}", &1.updated_at)) ++
        Enum.map(collections, &entry(base, "/collections/#{&1.handle}", &1.updated_at)) ++
        Enum.map(items, &entry(base, "/items/#{&1.handle}", &1.updated_at))

    xml =
      [
        ~s(<?xml version="1.0" encoding="UTF-8"?>\n),
        ~s(<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n),
        urls,
        ~s(</urlset>)
      ]
      |> IO.iodata_to_binary()

    conn
    |> put_resp_content_type("application/xml", "utf-8")
    |> put_resp_header("cache-control", "public, max-age=3600")
    |> send_resp(200, xml)
  end

  defp entry(base, path, updated_at) do
    lastmod = Calendar.strftime(updated_at, "%Y-%m-%d")

    [
      "  <url>\n",
      "    <loc>#{base}#{path}</loc>\n",
      "    <lastmod>#{lastmod}</lastmod>\n",
      "  </url>\n"
    ]
  end
end
