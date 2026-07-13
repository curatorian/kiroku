defmodule KirokuWeb.SEO do
  @moduledoc """
  Structured-data and social meta tags for item pages.

  Rendered inside the item LiveView body. Crawlers (Google Scholar, Google,
  Schema.org consumers, Facebook/Twitter/Slack scrapers) receive the
  server-rendered HTML and scan the full document, so body placement is fine
  and avoids the head-injection limitations of LiveView.
  """

  use KirokuWeb, :html

  alias Kiroku.Content
  alias KirokuWeb.Endpoint

  @thesis_types ~w(skripsi tesis disertasi tugas_akhir)a
  @article_types ~w(jurnal_nasional jurnal_internasional prosiding)a

  attr :item, :map, required: true
  attr :bitstreams, :list, default: []

  def item_meta(assigns) do
    assigns =
      assigns
      |> assign(:url, item_url(assigns.item))
      |> assign(:authors, author_names(assigns.item))
      |> assign(:date, publication_date(assigns.item))
      |> assign(:keywords, keyword_list(assigns.item))
      |> assign(:pdf_url, fulltext_pdf_url(assigns.bitstreams, assigns.item))
      |> assign(:json_ld, build_json_ld(assigns.item))
      |> assign(:description, item_description(assigns.item))
      |> assign(:site_name, Kiroku.Settings.brand_settings().name)

    ~H"""
    <%!-- Google Scholar citation_* tags (one citation_author per author) --%>
    <meta name="citation_title" content={@item.title} />
    <%= for author <- @authors do %>
      <meta name="citation_author" content={author} />
    <% end %>
    <meta :if={@date} name="citation_publication_date" content={@date} />
    <meta :if={@item.abstract} name="citation_abstract" content={@item.abstract} />
    <meta :if={@item.doi} name="citation_doi" content={@item.doi} />
    <meta :if={@item.language} name="citation_language" content={to_string(@item.language)} />
    <meta :if={@pdf_url} name="citation_pdf_url" content={@pdf_url} />
    <meta :if={@keywords != []} name="citation_keywords" content={Enum.join(@keywords, "; ")} />

    <%!-- Open Graph --%>
    <meta property="og:type" content="article" />
    <meta property="og:title" content={@item.title} />
    <meta property="og:description" content={@description} />
    <meta property="og:url" content={@url} />
    <meta property="og:site_name" content={@site_name} />
    <meta property="og:locale" content={locale_for(@item.language)} />

    <%!-- Twitter Card --%>
    <meta name="twitter:card" content="summary" />
    <meta name="twitter:title" content={@item.title} />
    <meta name="twitter:description" content={@description} />

    <%!-- Schema.org JSON-LD --%>
    <script type="application/ld+json">
      <%= Phoenix.HTML.raw(@json_ld) %>
    </script>
    """
  end

  # ── Helpers ────────────────────────────────────────────────────────────────

  defp item_url(%{handle: handle}) do
    Endpoint.url() <> ~p"/items/#{handle}"
  end

  defp author_names(%{item_authors: authors}) when is_list(authors) and authors != [] do
    Enum.map(authors, & &1.author_name)
  end

  defp author_names(%{student_name: name}) when is_binary(name) and name != "", do: [name]
  defp author_names(_), do: []

  defp publication_date(%{date_issued: %Date{} = d}),
    do: Calendar.strftime(d, "%Y/%m/%d")

  defp publication_date(%{publication_year: year}) when is_integer(year),
    do: to_string(year)

  defp publication_date(_), do: nil

  defp keyword_list(%{item_keywords: keywords}) when is_list(keywords),
    do: Enum.map(keywords, & &1.keyword)

  defp keyword_list(_), do: []

  defp item_description(%{abstract: abstract}) when is_binary(abstract) and abstract != "",
    do: String.slice(abstract, 0, 300)

  defp item_description(%{short_description: s}) when is_binary(s), do: s
  defp item_description(_), do: ""

  defp locale_for(:en), do: "en_US"
  defp locale_for(_), do: "id_ID"

  # Picks an anonymous-accessible ORIGINAL full-text bitstream (not the
  # abstract, which is seq 1) for Google Scholar's citation_pdf_url. Returns
  # nil when none is publicly downloadable.
  defp fulltext_pdf_url(bitstreams, item) do
    bs =
      Enum.find(bitstreams, fn bs ->
        bs.bundle_name == :ORIGINAL and bs.sequence != 1 and
          Content.accessible?(bs, nil, item)
      end)

    if bs, do: Endpoint.url() <> ~p"/items/#{item.handle}/bitstreams/#{bs.id}", else: nil
  end

  defp schema_type(item_type) when item_type in @thesis_types, do: "Thesis"
  defp schema_type(item_type) when item_type in @article_types, do: "ScholarlyArticle"
  defp schema_type(_), do: "CreativeWork"

  defp build_json_ld(item) do
    base = %{
      "@context": "https://schema.org",
      "@type": schema_type(item.item_type),
      headline: item.title,
      url: item_url(item),
      datePublished: json_date(item),
      inLanguage: item.language && to_string(item.language)
    }

    base =
      if item.abstract do
        Map.put(base, :description, item.abstract)
      else
        base
      end

    base =
      case author_names(item) do
        [] ->
          base

        names ->
          Map.put(base, :author, json_authors(item, names))
      end

    base =
      if item.doi do
        Map.put(base, :identifier, %{
          "@type" => "PropertyValue",
          propertyID: "DOI",
          value: item.doi
        })
      else
        base
      end

    base =
      case keyword_list(item) do
        [] -> base
        kws -> Map.put(base, :keywords, Enum.join(kws, ", "))
      end

    base
    |> reject_nil()
    |> Jason.encode!(pretty: true)
  end

  defp json_authors(item, names) do
    orcid_map =
      (item.item_authors || [])
      |> Enum.filter(& &1.orcid)
      |> Map.new(&{&1.author_name, &1.orcid})

    Enum.map(names, fn name ->
      author = %{"@type" => "Person", "name" => name}

      case Map.get(orcid_map, name) do
        nil -> author
        orcid -> Map.put(author, "@id", "https://orcid.org/#{orcid}")
      end
    end)
  end

  defp json_date(%{date_issued: %Date{} = d}), do: Date.to_iso8601(d)
  defp json_date(%{publication_year: y}) when is_integer(y), do: to_string(y)
  defp json_date(_), do: nil

  defp reject_nil(map), do: Map.reject(map, fn {_, v} -> is_nil(v) end)
end
