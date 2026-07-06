defmodule Kiroku.Saf.DublinCoreTest do
  use ExUnit.Case, async: true

  alias Kiroku.Saf.DublinCore

  describe "build_xml/2" do
    test "produces a dc file with no schema attribute" do
      xml =
        DublinCore.build_xml("dc", [
          %{element: "title", qualifier: "none", language: nil, value: "T"}
        ])

      assert xml =~ ~s(<dublin_core>)
      refute xml =~ ~s(schema="dc")
      assert xml =~ ~s(element="title")
      assert xml =~ ~s(qualifier="none")
      assert xml =~ ">T<"
    end

    test "includes the schema attribute for non-dc schemas" do
      xml =
        DublinCore.build_xml("local", [
          %{element: "faculty", qualifier: "none", language: nil, value: "Hukum"}
        ])

      assert xml =~ ~s(schema="local")
    end

    test "emits a language attribute only when present" do
      xml =
        DublinCore.build_xml("dc", [
          %{element: "description", qualifier: "abstract", language: "en", value: "Hi"},
          %{element: "title", qualifier: "none", language: nil, value: "T"}
        ])

      assert xml =~ ~s(language="en")
      # the title value has no language attribute
      title_match =
        ~r/element="title"[^>]*>/
        |> Regex.run(xml)

      assert title_match != nil
      refute hd(title_match) =~ "language="
    end

    test "escapes ampersands in values" do
      xml =
        DublinCore.build_xml("dc", [
          %{element: "title", qualifier: "none", language: nil, value: "Tom & Jerry"}
        ])

      assert xml =~ "Tom &amp; Jerry"
    end
  end

  describe "parse_xml/1 round-trip" do
    test "recovers values with their attributes and order" do
      original = [
        %{element: "title", qualifier: "none", language: nil, value: "A Tale"},
        %{element: "description", qualifier: "abstract", language: "en", value: "Abstract EN"},
        %{element: "subject", qualifier: "none", language: nil, value: "physics"}
      ]

      {:ok, parsed} = DublinCore.build_xml("dc", original) |> DublinCore.parse_xml()

      assert length(parsed) == 3

      assert Enum.at(parsed, 0) == %{
               element: "title",
               qualifier: "none",
               language: nil,
               value: "A Tale"
             }

      assert Enum.at(parsed, 1) == %{
               element: "description",
               qualifier: "abstract",
               language: "en",
               value: "Abstract EN"
             }
    end

    test "treats missing qualifier and empty qualifier as 'none'" do
      xml = """
      <dublin_core><dcvalue element="title">No Qualifier</dcvalue></dublin_core>
      """

      {:ok, [parsed]} = DublinCore.parse_xml(xml)
      assert parsed.qualifier == "none"
      assert parsed.value == "No Qualifier"
    end

    test "reads a metadata_local.xml schema file" do
      xml = """
      <dublin_core schema="local">
        <dcvalue element="faculty" qualifier="none">Hukum</dcvalue>
      </dublin_core>
      """

      {:ok, [parsed]} = DublinCore.parse_xml(xml)
      assert parsed.element == "faculty"
      assert parsed.value == "Hukum"
    end

    test "returns error tuple for a missing file path" do
      assert {:error, _} = DublinCore.parse_xml("/nonexistent/does-not-exist.xml")
    end
  end
end
