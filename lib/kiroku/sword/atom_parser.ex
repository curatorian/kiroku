defmodule Kiroku.Sword.AtomParser do
  @moduledoc """
  Parses inbound SWORD v2 Atom entries to extract metadata for item creation.

  Uses simple regex-based extraction rather than a full XML parser, because
  SWORD Atom entries are shallow and well-structured. This avoids the
  complexity of `:xmerl` namespace handling while covering the SWORD profile
  reliably.

  Expected Atom entry format:

      <entry xmlns="http://www.w3.org/2005/Atom"
             xmlns:dcterms="http://purl.org/dc/terms/">
        <title>Thesis Title</title>
        <dcterms:abstract>Abstract text...</dcterms:abstract>
        <dcterms:creator>Author Name</dcterms:creator>
        <dcterms:type>skripsi</dcterms:type>
      </entry>
  """

  @doc """
  Parses an Atom XML entry body and returns a map of item attrs suitable
  for `Repository.create_item/1`.

  Returns `{:ok, attrs}` or `{:error, reason}`.
  """
  def parse_entry(xml_string) when is_binary(xml_string) do
    # Basic well-formedness check — the entry must contain <entry and </entry>.
    unless String.contains?(xml_string, "<entry") do
      {:error, "not an Atom entry: missing <entry> root element"}
    else
      attrs = %{
        "title" => extract_tag(xml_string, "title"),
        "abstract" =>
          extract_tag(xml_string, "dcterms:abstract") || extract_tag(xml_string, "summary"),
        "item_type" => map_item_type(extract_tag(xml_string, "dcterms:type")),
        "student_name" =>
          extract_tag(xml_string, "dcterms:creator") ||
            extract_tag(xml_string, "author/name") ||
            extract_text_in_tag(xml_string, "name")
      }

      attrs = Map.filter(attrs, fn {_k, v} -> v != nil and v != "" end)

      if Map.has_key?(attrs, "title") do
        {:ok, attrs}
      else
        {:error, "missing required field: title"}
      end
    end
  end

  # Extracts the text content of `<tag>...</tag>` or `<ns:tag>...</ns:tag>`.
  # Handles namespaced tags by matching the local name with optional prefix.
  defp extract_tag(xml, tag_name) do
    # Match <tag> or <prefix:tag>, capturing content up to the closing tag.
    pattern = ~r/<(?:\w+:)?#{tag_name}[^>]*>(.*?)<\/(?:\w+:)?#{tag_name}>/s

    case Regex.run(pattern, xml) do
      [_, content] -> content |> String.trim() |> unescape_xml()
      _ -> nil
    end
  end

  # Fallback for nested tags like <author><name>...</name></author>
  defp extract_text_in_tag(xml, tag_name) do
    extract_tag(xml, tag_name)
  end

  defp unescape_xml(string) do
    string
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
  end

  # Map Dublin Core / SWORD type strings to Kiroku's item_type enum.
  defp map_item_type(nil), do: nil

  defp map_item_type(type) do
    type_lower = String.downcase(String.trim(type))

    cond do
      String.contains?(type_lower, "skripsi") -> "skripsi"
      String.contains?(type_lower, "thesis") -> "tesis"
      String.contains?(type_lower, "dissertation") -> "disertasi"
      String.contains?(type_lower, "article") -> "jurnal_nasional"
      String.contains?(type_lower, "proceeding") -> "prosiding"
      true -> "skripsi"
    end
  end
end
