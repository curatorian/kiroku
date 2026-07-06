defmodule Kiroku.Saf.DublinCore do
  @moduledoc """
  Read and write DSpace Simple Archive Format metadata files.

  Two physical files are produced per item:
    - `dublin_core.xml`        — the `dc` schema (DSpace-compatible subset)
    - `metadata_local.xml`     — the `local` schema (Kiroku-specific typed
                                 fields, for lossless Kiroku→Kiroku round-trips)

  Each `<dcvalue>` carries `element`, `qualifier`, and optional `language`
  attributes, exactly as documented in the DSpace SAF spec. Parsing tolerates
  the `schema` attribute on the root `<dublin_core>` element so files written
  by either DSpace or Kiroku can be read back.

  A "value" is represented internally as a map:

      %{element: "title", qualifier: "none", language: nil, value: "..."}

  This module is pure data transformation — no DB, no filesystem.
  """

  require Record

  # xmerl record from sweet_xml's dependency; we only parse with SweetXml's
  # higher-level xpath, so this is just to satisfy the Record def for xmerl.
  Record.defrecord(:xmlText, Record.extract(:xmlText, from_lib: "xmerl/include/xmerl.hrl"))

  @type value :: %{
          element: String.t(),
          qualifier: String.t() | nil,
          language: String.t() | nil,
          value: String.t()
        }

  @doc """
  Builds the XML text for one schema's metadata file.

  `schema` is `"dc"` or `"local"`. When `"dc"`, the root tag has no `schema`
  attribute (matching the DSpace `dublin_core.xml` convention); otherwise the
  `schema` attribute is set so DSpace/Kiroku can route values on import.
  """
  @spec build_xml(String.t(), [value()]) :: String.t()
  def build_xml(schema, values) do
    root_attrs = if schema == "dc", do: %{}, else: %{"schema" => schema}

    # Preserve input order — multi-value ordering (contributors, subjects) is
    # significant and must survive the round-trip.
    entries = Enum.map(values, fn v -> {:dcvalue, dcvalue_attrs(v), v.value} end)

    doc = {:dublin_core, root_attrs, entries}
    XmlBuilder.generate(doc, encoding: "UTF-8")
  end

  defp dcvalue_attrs(v) do
    base = %{"element" => v.element, "qualifier" => v.qualifier || "none"}

    if v.language do
      Map.put(base, "language", v.language)
    else
      base
    end
  end

  @doc """
  Parses a metadata XML file (path or binary) into a list of values.

  The returned values do NOT carry the schema — the caller knows which file it
  read. Values are returned in document order, which preserves multi-value
  ordering (important for contributors / subjects).
  """
  @spec parse_xml(binary()) :: {:ok, [value()]} | {:error, term()}
  def parse_xml(source) when is_binary(source) do
    case read_source(source) do
      {:ok, xml} ->
        {:ok, do_parse(xml)}

      {:error, _} = err ->
        err
    end
  end

  defp read_source(binary) when is_binary(binary) do
    # Heuristic: if it starts with "<" (after whitespace) treat it as inline XML,
    # otherwise treat it as a filesystem path. Avoids path-vs-content ambiguity.
    trimmed = String.trim_leading(binary)

    if String.starts_with?(trimmed, "<") do
      {:ok, binary}
    else
      File.read(binary)
    end
  end

  defp do_parse(xml) do
    import SweetXml

    # SweetXml returns a list of {element, qualifier, language, value} tuples
    # in document order.
    xml
    |> SweetXml.xpath(
      ~x"//dcvalue"l,
      element: ~x"./@element"s,
      qualifier: ~x"./@qualifier"s,
      language: ~x"./@language"s,
      value: ~x"./text()"s
    )
    |> Enum.map(fn row ->
      %{
        element: row.element,
        qualifier: normalize_qualifier(row.qualifier),
        language: normalize_language(row.language),
        value: row.value
      }
    end)
  end

  # DSpace uses the literal string "none" to mean "no qualifier".
  defp normalize_qualifier(""), do: "none"
  defp normalize_qualifier("none"), do: "none"
  defp normalize_qualifier(other), do: other

  defp normalize_language(""), do: nil
  defp normalize_language(nil), do: nil
  defp normalize_language(lang), do: lang
end
