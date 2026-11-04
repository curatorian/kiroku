defmodule KirokuWeb.Api.OaiSchemaTest do
  @moduledoc """
  Validates the OAI-PMH responses against the official OAI-PMH.xsd.

  The other OAI tests check well-formedness (`:xmerl_scan`) and specific
  content, but neither proves the document matches the schema harvesters
  validate against. Element ordering, required children, and attribute types
  are all constrained by the XSD, so a document can be well-formed and still
  be rejected by a harvester.

  The schemas in `test/fixtures/oai_pmh/` are the official files from
  openarchives.org, with two local adjustments so they resolve offline:

    * `OAI-PMH.xsd` imports `oai_dc.xsd` (the official file declares
      `<any namespace="##other" processContents="strict"/>`, which needs the
      metadata schema to be resolvable).
    * `oai_dc.xsd` imports the Dublin Core schema locally — the upstream
      `http://dublincore.org/...` URL is no longer served.

  The test is skipped when `xmllint` is not installed.
  """

  use KirokuWeb.ConnCase, async: true

  alias Kiroku.Repository

  @schema_dir Path.expand("../../../fixtures/oai_pmh", __DIR__)

  setup_all do
    if System.find_executable("xmllint") do
      {:ok, schema: Path.join(@schema_dir, "OAI-PMH.xsd")}
    else
      {:ok, skip: :no_xmllint}
    end
  end

  defp create_collection do
    handle = "comm-#{System.unique_integer([:positive])}"

    {:ok, community} =
      Repository.create_community(%{"name" => "Schema Test", "handle" => handle})

    {:ok, collection} =
      Repository.create_collection(%{
        "name" => "Schema Collection",
        "community_id" => community.id,
        "handle" => "coll-#{System.unique_integer([:positive])}"
      })

    {community, collection}
  end

  defp published_item(collection_id, attrs \\ %{}) do
    {:ok, item} =
      Repository.create_item(
        Map.merge(
          %{
            "title" => "Schema Item #{System.unique_integer([:positive])}",
            "collection_id" => collection_id,
            "status" => "published",
            "discoverable" => true,
            "access_level" => "open"
          },
          attrs
        )
      )

    item
  end

  defp oai(conn, params) do
    qs = Enum.map_join(params, "&", fn {k, v} -> "#{k}=#{v}" end)
    get(conn, "/api/oai?#{qs}")
  end

  # Validates an XML document against the schema with xmllint. Returns
  # :ok when the document is valid, or the validator's error output.
  #
  # xmllint writes the schema-compile warnings to stderr and the validation
  # result to stdout, so both are captured. The warnings are noise (about the
  # duplicate xml namespace import) and are filtered out of the failure output.
  defp validate_against_schema(xml, schema) do
    unique = System.unique_integer([:positive])
    path = Path.join(System.tmp_dir!(), "oai-schema-#{unique}.xml")
    err_path = Path.join(System.tmp_dir!(), "oai-schema-#{unique}.err")

    File.write!(path, xml)

    try do
      # stderr is redirected to a file so the schema-compile warnings (about
      # the duplicate xml namespace import) do not pollute the test output.
      {output, status} =
        System.cmd(
          "sh",
          ["-c", "xmllint --noout --schema #{schema} #{path} 2>#{err_path}"]
        )

      if status == 0 do
        :ok
      else
        {:error, output <> read_errors(err_path)}
      end
    after
      File.rm(path)
      File.rm(err_path)
    end
  end

  defp read_errors(path) do
    case File.read(path) do
      {:ok, contents} -> contents
      {:error, _} -> ""
    end
  end

  describe "schema conformance" do
    test "the Identify response validates", %{conn: conn, schema: schema} do
      body = response(oai(conn, %{"verb" => "Identify"}), 200)

      assert validate_against_schema(body, schema) == :ok
    end

    test "the ListMetadataFormats response validates", %{conn: conn, schema: schema} do
      body = response(oai(conn, %{"verb" => "ListMetadataFormats"}), 200)

      assert validate_against_schema(body, schema) == :ok
    end

    test "the ListSets response validates", %{conn: conn, schema: schema} do
      {_, collection} = create_collection()
      published_item(collection.id)

      body = response(oai(conn, %{"verb" => "ListSets"}), 200)

      assert validate_against_schema(body, schema) == :ok
    end

    test "the ListIdentifiers response validates", %{conn: conn, schema: schema} do
      {_, collection} = create_collection()
      published_item(collection.id)

      body =
        response(oai(conn, %{"verb" => "ListIdentifiers", "metadataPrefix" => "oai_dc"}), 200)

      assert validate_against_schema(body, schema) == :ok
    end

    test "the ListRecords response validates", %{conn: conn, schema: schema} do
      {_, collection} = create_collection()

      published_item(collection.id, %{
        "abstract" => "An abstract with “smart quotes” and an emoji \u{1F600}.",
        "publication_year" => 2015
      })

      body = response(oai(conn, %{"verb" => "ListRecords", "metadataPrefix" => "oai_dc"}), 200)

      assert validate_against_schema(body, schema) == :ok
    end

    test "the GetRecord response validates", %{conn: conn, schema: schema} do
      {_, collection} = create_collection()
      item = published_item(collection.id)

      body =
        response(
          oai(conn, %{
            "verb" => "GetRecord",
            "metadataPrefix" => "oai_dc",
            "identifier" => "oai:kiroku.ac.id:#{item.id}"
          }),
          200
        )

      assert validate_against_schema(body, schema) == :ok
    end

    test "the error responses validate", %{conn: conn, schema: schema} do
      bad_verb = response(oai(conn, %{"verb" => "Frobnicate"}), 200)
      assert validate_against_schema(bad_verb, schema) == :ok

      bad_argument = response(oai(conn, %{"verb" => "Identify", "from" => "2024-01-01"}), 200)
      assert validate_against_schema(bad_argument, schema) == :ok

      no_records =
        response(
          oai(conn, %{
            "verb" => "ListRecords",
            "metadataPrefix" => "oai_dc",
            "set" => "col_00000000-0000-0000-0000-000000000000"
          }),
          200
        )

      assert validate_against_schema(no_records, schema) == :ok
    end

    test "a repeated argument response validates", %{conn: conn, schema: schema} do
      body = response(get(conn, "/api/oai?verb=Identify&verb=ListSets"), 200)

      assert validate_against_schema(body, schema) == :ok
    end
  end
end
