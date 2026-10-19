defmodule KirokuWeb.OaiControllerTest do
  use KirokuWeb.ConnCase, async: true

  alias Kiroku.Repository

  defp create_collection do
    handle = "comm-#{System.unique_integer([:positive])}"

    {:ok, community} =
      Repository.create_community(%{"name" => "Fakultas Test", "handle" => handle})

    {:ok, collection} =
      Repository.create_collection(%{
        "name" => "Collection Test",
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
            "title" => "Thesis #{System.unique_integer([:positive])}",
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
    get(conn, "/oai?#{qs}")
  end

  defp extract_token(xml) do
    case Regex.run(~r/<resumptionToken[^>]*>([^<]+)<\/resumptionToken>/, xml) do
      [_, token] -> token
      nil -> nil
    end
  end

  describe "Identify" do
    test "returns repository metadata", %{conn: conn} do
      body = response(oai(conn, %{"verb" => "Identify"}), 200)

      assert body =~ "<Identify>"
      assert body =~ "protocolVersion>2.0"
      assert body =~ "granularity>YYYY-MM-DDThh:mm:ssZ"
    end

    test "uses the configured repository name and admin e-mail", %{conn: conn} do
      Kiroku.Settings.put("oai_repo_name", "Universitas Padjadjaran Repository")
      Kiroku.Settings.put("oai_admin_email", "repository@unpad.ac.id")

      body = response(oai(conn, %{"verb" => "Identify"}), 200)

      assert body =~ "<repositoryName>Universitas Padjadjaran Repository</repositoryName>"
      assert body =~ "<adminEmail>repository@unpad.ac.id</adminEmail>"
      refute body =~ "Kiroku Institutional Repository"
      refute body =~ "admin@kiroku.ac.id"
    end
  end

  describe "ListMetadataFormats" do
    test "advertises oai_dc", %{conn: conn} do
      body = response(oai(conn, %{"verb" => "ListMetadataFormats"}), 200)

      assert body =~ "<metadataPrefix>oai_dc</metadataPrefix>"
    end
  end

  describe "ListSets" do
    test "exposes both communities and collections as sets", %{conn: conn} do
      {community, collection} = create_collection()

      body = response(oai(conn, %{"verb" => "ListSets"}), 200)

      assert body =~ "com_#{community.id}"
      assert body =~ "col_#{collection.id}"
    end
  end

  describe "ListRecords" do
    test "returns oai_dc records", %{conn: conn} do
      {_, collection} = create_collection()
      item = published_item(collection.id, %{"abstract" => "Sebuah abstrak."})

      body = response(oai(conn, %{"verb" => "ListRecords", "metadataPrefix" => "oai_dc"}), 200)

      assert body =~ "<record>"
      assert body =~ item.title
      assert body =~ "<dc:title>"
    end

    test "paginates with resumptionToken", %{conn: conn} do
      {_, collection} = create_collection()

      items = for _ <- 1..5, do: published_item(collection.id)
      titles = Enum.map(items, & &1.title) |> MapSet.new()

      # Page size is 3 in test config — first page returns 3 + a token.
      first = response(oai(conn, %{"verb" => "ListRecords", "metadataPrefix" => "oai_dc"}), 200)

      token = extract_token(first)
      assert token, "expected a resumptionToken on the first page"

      first_count = Regex.scan(~r/<record>/, first) |> length()
      assert first_count == 3
      assert first =~ ~s(completeListSize="5")

      # Second page via token returns the remaining 2 and no further token.
      second = response(oai(conn, %{"verb" => "ListRecords", "resumptionToken" => token}), 200)

      second_count = Regex.scan(~r/<record>/, second) |> length()
      assert second_count == 2
      assert extract_token(second) == nil

      # All 5 records appear across the two pages.
      all_titles =
        (Regex.scan(~r/<dc:title>([^<]+)<\/dc:title>/, first) ++
           Regex.scan(~r/<dc:title>([^<]+)<\/dc:title>/, second))
        |> Enum.map(fn [_, t] -> t end)
        |> MapSet.new()

      assert MapSet.subset?(titles, all_titles)
    end

    test "uses the configured repository identifier", %{conn: conn} do
      {_, collection} = create_collection()
      item = published_item(collection.id)

      Kiroku.Settings.put("oai_repo_identifier", "oai:repository.unpad.ac.id")

      body = response(oai(conn, %{"verb" => "ListRecords", "metadataPrefix" => "oai_dc"}), 200)

      assert body =~ "oai:repository.unpad.ac.id:#{item.id}"
      refute body =~ "oai:kiroku.ac.id:#{item.id}"
    end

    test "set filter scopes to a collection", %{conn: conn} do
      {_, coll_a} = create_collection()
      {_, coll_b} = create_collection()

      item_a = published_item(coll_a.id)
      _item_b = published_item(coll_b.id)

      body =
        response(
          oai(conn, %{
            "verb" => "ListRecords",
            "metadataPrefix" => "oai_dc",
            "set" => "col_#{coll_a.id}"
          }),
          200
        )

      assert body =~ item_a.title
      assert Regex.scan(~r/<record>/, body) |> length() == 1
    end

    test "from/until: future from yields noRecordsMatch", %{conn: conn} do
      {_, collection} = create_collection()
      published_item(collection.id)

      # Seconds-granularity dates must match the exact format the spec
      # declares (YYYY-MM-DDThh:mm:ssZ) — fractional seconds are illegal.
      future =
        DateTime.utc_now()
        |> DateTime.add(86_400, :second)
        |> DateTime.truncate(:second)
        |> DateTime.to_iso8601()

      body =
        response(
          oai(conn, %{"verb" => "ListRecords", "metadataPrefix" => "oai_dc", "from" => future}),
          200
        )

      assert body =~ ~s(code="noRecordsMatch")
    end

    test "from: past date returns all records", %{conn: conn} do
      {_, collection} = create_collection()
      published_item(collection.id)

      past =
        DateTime.utc_now()
        |> DateTime.add(-86_400, :second)
        |> DateTime.truncate(:second)
        |> DateTime.to_iso8601()

      body =
        response(
          oai(conn, %{"verb" => "ListRecords", "metadataPrefix" => "oai_dc", "from" => past}),
          200
        )

      assert body =~ "<record>"
    end

    test "badResumptionToken on an invalid token", %{conn: conn} do
      body =
        response(
          oai(conn, %{"verb" => "ListRecords", "resumptionToken" => "not-a-real-token"}),
          200
        )

      assert body =~ ~s(code="badResumptionToken")
    end

    test "missing metadataPrefix is badArgument", %{conn: conn} do
      body = response(oai(conn, %{"verb" => "ListRecords"}), 200)
      assert body =~ ~s(code="badArgument")
    end
  end

  describe "ListIdentifiers" do
    test "returns headers without metadata", %{conn: conn} do
      {_, collection} = create_collection()
      published_item(collection.id)

      body =
        response(oai(conn, %{"verb" => "ListIdentifiers", "metadataPrefix" => "oai_dc"}), 200)

      assert body =~ "<ListIdentifiers>"
      assert body =~ "<header>"
      assert body =~ "<identifier>"
      refute body =~ "<dc:title>"
    end
  end

  describe "GetRecord" do
    test "fetches a single record by OAI identifier", %{conn: conn} do
      {_, collection} = create_collection()
      item = published_item(collection.id, %{"abstract" => "Abstrak unik."})

      identifier = "oai:kiroku.ac.id:#{item.id}"

      body =
        response(
          oai(conn, %{
            "verb" => "GetRecord",
            "metadataPrefix" => "oai_dc",
            "identifier" => identifier
          }),
          200
        )

      assert body =~ item.title
      assert body =~ "Abstrak unik."
    end

    test "GetRecord accepts the configured identifier prefix", %{conn: conn} do
      {_, collection} = create_collection()
      item = published_item(collection.id, %{"abstract" => "Abstrak unik."})

      Kiroku.Settings.put("oai_repo_identifier", "oai:repository.unpad.ac.id")

      body =
        response(
          oai(conn, %{
            "verb" => "GetRecord",
            "metadataPrefix" => "oai_dc",
            "identifier" => "oai:repository.unpad.ac.id:#{item.id}"
          }),
          200
        )

      assert body =~ item.title
      assert body =~ "Abstrak unik."
    end

    test "idDoesNotExist for unknown identifier", %{conn: conn} do
      body =
        response(
          oai(conn, %{
            "verb" => "GetRecord",
            "metadataPrefix" => "oai_dc",
            "identifier" => "oai:kiroku.ac.id:nope"
          }),
          200
        )

      assert body =~ ~s(code="idDoesNotExist")
    end
  end

  describe "errors" do
    test "badVerb for an unknown verb", %{conn: conn} do
      body = response(oai(conn, %{"verb" => "Frobnicate"}), 200)
      assert body =~ ~s(code="badVerb")
    end

    test "cannotDisseminateFormat for unsupported prefix", %{conn: conn} do
      body =
        response(oai(conn, %{"verb" => "ListRecords", "metadataPrefix" => "proc_xml"}), 200)

      assert body =~ ~s(code="cannotDisseminateFormat")
    end
  end

  describe "spec conformance (OAI-PMH.xsd)" do
    test "error responses carry the mandatory <request> element", %{conn: conn} do
      {_, collection} = create_collection()
      published_item(collection.id)

      body =
        response(
          oai(conn, %{"verb" => "ListRecords", "metadataPrefix" => "oai_dc", "set" => "col_none"}),
          200
        )

      assert body =~ "<request verb=\"ListRecords\" metadataPrefix=\"oai_dc\" set=\"col_none\">"
      assert body =~ ~s(code="noRecordsMatch")
      # responseDate/request/error element order enforced by the XSD
      assert Regex.run(~r/<responseDate>.*?<request[^>]*>.*?<error/s, body) != nil
    end

    test "badVerb / badArgument echo the bare base URL without attributes", %{conn: conn} do
      bad_verb = response(oai(conn, %{"verb" => "Frobnicate"}), 200)
      assert bad_verb =~ "<request>http://localhost:4000/oai</request>"
      refute bad_verb =~ ~r/<request [^>]/

      bad_arg = response(oai(conn, %{"verb" => "Identify", "from" => "2024-01-01"}), 200)
      assert bad_arg =~ ~s(code="badArgument")
      assert bad_arg =~ "<request>http://localhost:4000/oai</request>"
      refute bad_arg =~ ~r/<request [^>]/
    end

    test "illegal arguments yield badArgument", %{conn: conn} do
      body = response(oai(conn, %{"verb" => "ListSets", "set" => "col_none"}), 200)
      assert body =~ ~s(code="badArgument")
    end

    test "resumptionToken must be the only argument", %{conn: conn} do
      body =
        response(
          oai(conn, %{"verb" => "ListRecords", "resumptionToken" => "abc", "from" => "2024-01-01"}),
          200
        )

      assert body =~ ~s(code="badArgument")
    end

    test "mixed from/until granularity is badArgument", %{conn: conn} do
      body =
        response(
          oai(conn, %{
            "verb" => "ListRecords",
            "metadataPrefix" => "oai_dc",
            "from" => "2024-01-01",
            "until" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
          }),
          200
        )

      assert body =~ ~s(code="badArgument")
      assert body =~ "same granularity"
    end

    test "from after until is badArgument", %{conn: conn} do
      body =
        response(
          oai(conn, %{
            "verb" => "ListRecords",
            "metadataPrefix" => "oai_dc",
            "from" => "2024-02-01",
            "until" => "2024-01-01"
          }),
          200
        )

      assert body =~ ~s(code="badArgument")
    end

    test "malformed metadataPrefix is badArgument", %{conn: conn} do
      body = response(oai(conn, %{"verb" => "GetRecord"}), 200)
      assert body =~ ~s(code="badArgument")
    end

    test "record headers include setSpec membership", %{conn: conn} do
      {community, collection} = create_collection()
      item = published_item(collection.id)

      records = response(oai(conn, %{"verb" => "ListRecords", "metadataPrefix" => "oai_dc"}), 200)

      headers =
        response(oai(conn, %{"verb" => "ListIdentifiers", "metadataPrefix" => "oai_dc"}), 200)

      single =
        response(
          oai(conn, %{
            "verb" => "GetRecord",
            "metadataPrefix" => "oai_dc",
            "identifier" => "oai:kiroku.ac.id:#{item.id}"
          }),
          200
        )

      assert records =~ "<setSpec>col_#{collection.id}</setSpec>"
      assert records =~ "<setSpec>com_#{community.id}</setSpec>"
      assert headers =~ "<setSpec>col_#{collection.id}</setSpec>"
      assert headers =~ "<setSpec>com_#{community.id}</setSpec>"
      assert single =~ "<setSpec>com_#{community.id}</setSpec>"
    end

    test "final paginated page carries an empty resumptionToken", %{conn: conn} do
      {_, collection} = create_collection()
      for _ <- 1..5, do: published_item(collection.id)

      first = response(oai(conn, %{"verb" => "ListRecords", "metadataPrefix" => "oai_dc"}), 200)
      token = extract_token(first)

      second = response(oai(conn, %{"verb" => "ListRecords", "resumptionToken" => token}), 200)

      # §3.5: the response completing the list includes an EMPTY token element
      assert second =~ ~s(<resumptionToken completeListSize="5" cursor="3"/>)
    end

    test "unknown set yields noRecordsMatch instead of silently listing everything", %{conn: conn} do
      {_, collection} = create_collection()
      published_item(collection.id)

      body =
        response(
          oai(conn, %{
            "verb" => "ListRecords",
            "metadataPrefix" => "oai_dc",
            "set" => "col_0000"
          }),
          200
        )

      assert body =~ ~s(code="noRecordsMatch")
      refute body =~ "<record>"
    end

    test "ListMetadataFormats returns idDoesNotExist for an unknown identifier", %{conn: conn} do
      body =
        response(
          oai(
            conn,
            %{"verb" => "ListMetadataFormats", "identifier" => "oai:kiroku.ac.id:nope"}
          ),
          200
        )

      assert body =~ ~s(code="idDoesNotExist")
    end

    test "earliestDatestamp is a guaranteed lower bound of record datestamps", %{conn: conn} do
      {_, collection} = create_collection()
      item = published_item(collection.id)

      identify = response(oai(conn, %{"verb" => "Identify"}), 200)

      [earliest] =
        Regex.run(~r/<earliestDatestamp>([^<]+)<\/earliestDatestamp>/, identify) |> tl()

      first_page =
        response(oai(conn, %{"verb" => "ListRecords", "metadataPrefix" => "oai_dc"}), 200)

      [datestamp] = Regex.run(~r/<datestamp>([^<]+)<\/datestamp>/, first_page) |> tl()

      earliest_date = Date.from_iso8601!(String.slice(earliest, 0, 10))
      record_date = Date.from_iso8601!(String.slice(datestamp, 0, 10))
      assert Date.compare(earliest_date, record_date) != :gt
      assert item.updated_at != nil
    end

    test "GetRecord hides items that are not public/open", %{conn: conn} do
      {_, collection} = create_collection()
      item = published_item(collection.id, %{"access_level" => "restricted"})

      identifier = "oai:kiroku.ac.id:#{item.id}"

      body =
        response(
          oai(conn, %{
            "verb" => "GetRecord",
            "metadataPrefix" => "oai_dc",
            "identifier" => identifier
          }),
          200
        )

      assert body =~ ~s(code="idDoesNotExist")
      refute body =~ item.title
    end

    test "GetRecord with a missing identifier is badArgument", %{conn: conn} do
      body = response(oai(conn, %{"verb" => "GetRecord", "metadataPrefix" => "oai_dc"}), 200)
      assert body =~ ~s(code="badArgument")
    end

    test "ListSets with an invalid token is badResumptionToken", %{conn: conn} do
      body = response(oai(conn, %{"verb" => "ListSets", "resumptionToken" => "junk"}), 200)
      assert body =~ ~s(code="badResumptionToken")
    end
  end

  describe "oai_dc mapping hygiene" do
    defp create_authored_item(collection_id) do
      item =
        published_item(collection_id, %{
          "abstract" => "Abstrak.",
          "journal_name" => "Jurnal Testing",
          "conference_name" => "Symposium",
          "publisher" => "Perpustakaan"
        })

      {:ok, _} =
        Kiroku.Repository.create_item_author(%{
          "item_id" => item.id,
          "author_name" => "Sari Dewi",
          "sequence" => 1
        })

      {:ok, _} =
        Kiroku.Repository.create_item_author(%{
          "item_id" => item.id,
          "author_name" => "NULL",
          "sequence" => 99
        })

      {:ok, _} =
        Kiroku.Repository.create_item_author(%{
          "item_id" => item.id,
          "author_name" => "Budi Santoso",
          "sequence" => 2
        })

      _keywords =
        Kiroku.Repository.upsert_keywords_for_item(item.id, [
          %{keyword: "ethnography"},
          %{keyword: "null"}
        ])

      item
    end

    test "primary creator first, additional authors as contributors", %{conn: conn} do
      {_, collection} = create_collection()
      _item = create_authored_item(collection.id)

      body = response(oai(conn, %{"verb" => "ListRecords", "metadataPrefix" => "oai_dc"}), 200)

      creators = Regex.scan(~r/<dc:creator>([^<]+)<\/dc:creator>/, body)
      contributors = Regex.scan(~r/<dc:contributor>([^<]+)<\/dc:contributor>/, body)

      assert match?([[_full, "Sari Dewi"]], creators),
             "exactly one dc:creator, the primary author"

      assert match?([[_full, "Budi Santoso"]], contributors),
             "co-author demoted to dc:contributor"
    end

    test "literal NULL values are dropped, never emitted as content", %{conn: conn} do
      {_, collection} = create_collection()
      create_authored_item(collection.id)

      body = response(oai(conn, %{"verb" => "ListRecords", "metadataPrefix" => "oai_dc"}), 200)

      refute body =~ ">NULL<"
      refute body =~ ">null<"
      assert body =~ "<dc:subject>ethnography</dc:subject>"
    end

    test "emits dc:source from the containing publication", %{conn: conn} do
      {_, collection} = create_collection()
      create_authored_item(collection.id)

      body = response(oai(conn, %{"verb" => "ListRecords", "metadataPrefix" => "oai_dc"}), 200)

      assert body =~ "<dc:source>Jurnal Testing</dc:source>"
      assert body =~ "<dc:source>Symposium</dc:source>"
    end
  end
end
