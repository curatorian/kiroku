defmodule Kiroku.Export.Citation do
  @moduledoc """
  Generates citation strings and structured data for repository items.

  Supported formats:
  - `:apa`     — APA 7th Edition
  - `:mla`     — MLA 9th Edition
  - `:chicago` — Chicago 17th Edition (Author-Date)
  - `:ieee`    — IEEE Reference Format
  - `:bibtex`  — BibTeX/LaTeX
  - `:ris`     — RIS (EndNote, Zotero, Mendeley)
  """

  alias Kiroku.Repository.Item

  @doc """
  Generates a citation string for the given item and format.
  Returns `{:ok, citation_string}` or `{:error, reason}`.
  """
  def generate(%Item{} = item, format, preloads \\ %{}) do
    try do
      citation = format(item, format, preloads)
      {:ok, citation}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  @doc """
  Returns the MIME type for the given format.
  """
  def mime_type(:bibtex), do: "application/x-bibtex"
  def mime_type(:ris), do: "application/x-research-info-systems"
  def mime_type(_), do: "text/plain"

  @doc """
  Returns the file extension for the given format.
  """
  def file_extension(:bibtex), do: "bib"
  def file_extension(:ris), do: "ris"
  def file_extension(_), do: "txt"

  # ── Format implementations ─────────────────────────────────────────────

  defp format(item, :apa, preloads) do
    authors = format_authors_apa(preloads[:authors] || [])
    year = item.publication_year || "n.d."
    title = item.title || "Untitled"
    institution = item.institution || item.department || ""
    url = item_url(item)

    cond do
      item.item_type in [:jurnal_nasional, :jurnal_internasional] ->
        journal = item.journal_name || ""
        volume = item.volume
        issue = item.issue
        pages = format_pages(item.page_start, item.page_end)
        doi = if item.doi, do: " https://doi.org/#{item.doi}", else: ""

        vol_issue =
          cond do
            volume && issue -> "#{volume}(#{issue})"
            volume -> "#{volume}"
            true -> ""
          end

        "#{authors}(#{year}). #{title}. *#{journal}*, #{vol_issue}, #{pages}.#{doi}"

      item.item_type == :prosiding ->
        conference = item.conference_name || ""
        "#{authors}(#{year}). #{title}. *#{conference}*.#{if url != "", do: " #{url}"}"

      true ->
        type_label = degree_label(item)

        "#{authors}(#{year}). *#{title}* [#{type_label}]. #{institution}.#{if url != "", do: " #{url}"}"
    end
  end

  defp format(item, :mla, preloads) do
    authors = format_authors_mla(preloads[:authors] || [])
    title = item.title || "Untitled"
    year = item.publication_year || "n.d."
    institution = item.institution || item.department || ""
    url = item_url(item)

    cond do
      item.item_type in [:jurnal_nasional, :jurnal_internasional] ->
        journal = item.journal_name || ""
        volume = item.volume
        issue = item.issue
        pages = format_pages(item.page_start, item.page_end)

        vol_issue =
          cond do
            volume && issue -> "vol. #{volume}, no. #{issue}"
            volume -> "vol. #{volume}"
            true -> ""
          end

        "#{authors}\"#{title}.\" *#{journal}*, #{vol_issue}, #{year}, pp. #{pages}."

      item.item_type == :prosiding ->
        conference = item.conference_name || ""
        "#{authors}\"#{title}.\" *#{conference}*, #{year}.#{if url != "", do: " #{url}"}"

      true ->
        type_label = degree_label(item)

        "#{authors}*#{title}*. #{type_label}, #{institution}, #{year}.#{if url != "", do: " #{url}"}"
    end
  end

  defp format(item, :chicago, preloads) do
    authors = format_authors_chicago(preloads[:authors] || [])
    title = item.title || "Untitled"
    year = item.publication_year || "n.d."
    institution = item.institution || item.department || ""
    url = item_url(item)

    cond do
      item.item_type in [:jurnal_nasional, :jurnal_internasional] ->
        journal = item.journal_name || ""
        volume = item.volume
        issue = item.issue
        pages = format_pages(item.page_start, item.page_end)

        vol_issue =
          cond do
            volume && issue -> "#{volume}, no. #{issue}"
            volume -> "#{volume}"
            true -> ""
          end

        "#{authors}#{year}. \"#{title}.\" *#{journal}* #{vol_issue}: #{pages}."

      item.item_type == :prosiding ->
        conference = item.conference_name || ""

        "#{authors}#{year}. \"#{title}.\" Paper presented at #{conference}.#{if url != "", do: " #{url}"}"

      true ->
        type_label = degree_label(item)

        "#{authors}#{year}. \"#{title}.\" #{type_label}, #{institution}.#{if url != "", do: " #{url}"}"
    end
  end

  defp format(item, :ieee, preloads) do
    authors = format_authors_ieee(preloads[:authors] || [])
    title = item.title || "Untitled"
    year = item.publication_year || "n.d."
    institution = item.institution || item.department || ""
    url = item_url(item)

    cond do
      item.item_type in [:jurnal_nasional, :jurnal_internasional] ->
        journal = item.journal_name || ""
        volume = item.volume
        issue = item.issue
        pages = format_pages(item.page_start, item.page_end)

        vol_issue =
          cond do
            volume && issue -> "vol. #{volume}, no. #{issue}"
            volume -> "vol. #{volume}"
            true -> ""
          end

        doi_part = if item.doi, do: ", doi: #{item.doi}", else: ""
        "#{authors}\"#{title},\" *#{journal}*, #{vol_issue}, pp. #{pages}, #{year}#{doi_part}."

      item.item_type == :prosiding ->
        conference = item.conference_name || ""

        "#{authors}\"#{title},\" in *#{conference}*, #{year}#{if url != "", do: ", [Online]. Available: #{url}"}."

      true ->
        type_label = degree_label(item)
        url_part = if url != "", do: ", [Online]. Available: #{url}", else: ""
        "#{authors}\"#{title},\" #{type_label}, #{institution}, #{year}#{url_part}."
    end
  end

  defp format(item, :bibtex, preloads) do
    authors = format_authors_bibtex(preloads[:authors] || [])
    key = bibtex_key(item, preloads[:authors] || [])
    year = item.publication_year || "0"
    title = item.title || "Untitled"
    institution = item.institution || item.department || ""
    url = item_url(item)

    entry_type =
      cond do
        item.item_type in [:jurnal_nasional, :jurnal_internasional] -> "@article"
        item.item_type == :prosiding -> "@inproceedings"
        true -> "@mastersthesis"
      end

    fields =
      [
        {"title", title},
        {"author", authors},
        {"year", to_string(year)},
        if(item.item_type in [:jurnal_nasional, :jurnal_internasional],
          do: {"journal", item.journal_name || ""},
          else: nil
        ),
        if(item.item_type == :prosiding,
          do: {"booktitle", item.conference_name || ""},
          else: nil
        ),
        if(item.item_type not in [:jurnal_nasional, :jurnal_internasional, :prosiding],
          do: {"school", institution},
          else: nil
        ),
        if(item.volume, do: {"volume", item.volume}, else: nil),
        if(item.issue, do: {"number", item.issue}, else: nil),
        if(item.page_start,
          do: {"pages", format_pages(item.page_start, item.page_end)},
          else: nil
        ),
        if(item.doi, do: {"doi", item.doi}, else: nil),
        if(url != "", do: {"url", url}, else: nil)
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.map_join(",\n  ", fn {k, v} -> "#{k} = {#{v}}" end)

    "#{entry_type}{#{key},\n  #{fields}\n}"
  end

  defp format(item, :ris, preloads) do
    authors = preloads[:authors] || []
    year = item.publication_year || "0000"
    title = item.title || "Untitled"
    institution = item.institution || item.department || ""
    url = item_url(item)

    type_tag =
      cond do
        item.item_type in [:jurnal_nasional, :jurnal_internasional] -> "JOUR"
        item.item_type == :prosiding -> "CONF"
        true -> "THES"
      end

    au_lines = Enum.map_join(authors, "\n", fn a -> "AU  - #{a.author_name}" end)

    keywords =
      if preloads[:keywords] && preloads[:keywords] != [] do
        preloads[:keywords]
        |> Enum.map_join("\n", fn k -> "KW  - #{k.keyword}" end)
      else
        ""
      end

    lines =
      [
        "TY  - #{type_tag}",
        "TI  - #{title}",
        au_lines,
        "PY  - #{year}",
        if(item.item_type in [:jurnal_nasional, :jurnal_internasional],
          do: "JO  - #{item.journal_name || ""}",
          else: nil
        ),
        if(item.volume, do: "VL  - #{item.volume}", else: nil),
        if(item.issue, do: "IS  - #{item.issue}", else: nil),
        if(item.page_start, do: "SP  - #{item.page_start}", else: nil),
        if(item.page_end, do: "EP  - #{item.page_end}", else: nil),
        if(item.doi, do: "DO  - #{item.doi}", else: nil),
        if(institution != "", do: "PB  - #{institution}", else: nil),
        if(item.abstract, do: "AB  - #{item.abstract}", else: nil),
        keywords,
        if(url != "", do: "UR  - #{url}", else: nil),
        "ER  -"
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n")

    lines
  end

  # ── Author formatting helpers ─────────────────────────────────────────────

  defp format_authors_apa([]), do: ""

  defp format_authors_apa(authors) do
    formatted =
      Enum.map(authors, fn a ->
        parts = String.split(a.author_name, " ", trim: true)

        case parts do
          [last] ->
            last

          [first | rest] ->
            last = List.last(rest)
            initials = [first | Enum.drop(rest, -1)] |> Enum.map_join("", &"#{String.first(&1)}.")
            "#{last}, #{initials}"
        end
      end)

    count = length(formatted)

    case count do
      1 ->
        "#{hd(formatted)}. "

      2 ->
        "#{Enum.at(formatted, 0)}, & #{Enum.at(formatted, 1)}. "

      _ when count <= 20 ->
        "#{Enum.join(Enum.drop(formatted, -1), ", ")}, & #{List.last(formatted)}. "

      _ ->
        "#{Enum.at(formatted, 0)}, et al. "
    end
  end

  defp format_authors_mla([]), do: ""

  defp format_authors_mla(authors) do
    case length(authors) do
      0 ->
        ""

      1 ->
        "#{hd(authors).author_name}. "

      2 ->
        "#{Enum.at(authors, 0).author_name}, and #{Enum.at(authors, 1).author_name}. "

      _ ->
        "#{hd(authors).author_name}, et al. "
    end
  end

  defp format_authors_chicago([]), do: ""

  defp format_authors_chicago(authors) do
    case length(authors) do
      0 -> ""
      1 -> "#{hd(authors).author_name}. "
      2 -> "#{Enum.at(authors, 0).author_name} and #{Enum.at(authors, 1).author_name}. "
      _ -> "#{hd(authors).author_name} et al. "
    end
  end

  defp format_authors_ieee([]), do: ""

  defp format_authors_ieee(authors) do
    formatted =
      Enum.map(authors, fn a ->
        parts = String.split(a.author_name, " ", trim: true)

        case parts do
          [last] ->
            last

          [first | rest] ->
            last = List.last(rest)
            initials = [first | Enum.drop(rest, -1)] |> Enum.map_join(". ", &String.first/1)
            "#{initials}. #{last}"
        end
      end)

    case length(formatted) do
      0 -> ""
      1 -> "#{hd(formatted)}, "
      2 -> "#{Enum.join(formatted, " and ")}, "
      _ -> "#{Enum.join(Enum.drop(formatted, -1), ", ")}, and #{List.last(formatted)}, "
    end
  end

  defp format_authors_bibtex([]), do: "Unknown"

  defp format_authors_bibtex(authors) do
    authors
    |> Enum.map(& &1.author_name)
    |> Enum.join(" and ")
  end

  # ── Misc helpers ──────────────────────────────────────────────────────────

  defp format_pages(nil, nil), do: ""
  defp format_pages(start, nil), do: to_string(start)
  defp format_pages(start, stop), do: "#{start}–#{stop}"

  defp degree_label(%Item{item_type: :skripsi, degree_level: level}) do
    case level do
      :s2 -> "Master's Thesis"
      :s3 -> "Doctoral Dissertation"
      _ -> "Undergraduate Thesis"
    end
  end

  defp degree_label(%Item{item_type: :memorandum_hukum}), do: "Legal Memorandum"
  defp degree_label(%Item{item_type: :studi_kasus}), do: "Case Study"
  defp degree_label(%Item{item_type: :laporan_proyek}), do: "Project Report"
  defp degree_label(%Item{item_type: :karya_kreatif}), do: "Creative Work"
  defp degree_label(%Item{item_type: :karya_teknologi}), do: "Technology Work"
  defp degree_label(%Item{item_type: :capstone}), do: "Capstone Project"
  defp degree_label(_), do: "Thesis"

  defp bibtex_key(item, []) do
    year = item.publication_year || "0000"
    slug = item.title |> String.downcase() |> String.slice(0, 20) |> String.replace(~r/[^\w]/, "")
    "kiroku#{year}#{slug}"
  end

  defp bibtex_key(item, [first_author | _]) do
    year = item.publication_year || "0000"
    last = first_author.author_name |> String.split(" ") |> List.last() |> String.downcase()
    "#{last}#{year}"
  end

  defp item_url(item) do
    handle = item.handle || item.id
    base = Application.get_env(:kiroku, KirokuWeb.Endpoint, []) |> Keyword.get(:url, [])
    host = Keyword.get(base, :host, "")

    if host != "" do
      scheme = if Keyword.get(base, :scheme, "https") == "https", do: "https", else: "http"
      "#{scheme}://#{host}/items/#{handle}"
    else
      ""
    end
  end
end
