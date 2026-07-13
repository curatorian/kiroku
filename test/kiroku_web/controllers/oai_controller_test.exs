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

      future = DateTime.utc_now() |> DateTime.add(86_400, :second) |> DateTime.to_iso8601()

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

      past = DateTime.utc_now() |> DateTime.add(-86_400, :second) |> DateTime.to_iso8601()

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
end
