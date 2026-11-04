defmodule KirokuWeb.OaiLiveTest do
  use KirokuWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

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

  describe "the /oai page" do
    test "renders the OAI-PMH UI", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/oai")

      assert html =~ "OAI-PMH Endpoint"
      assert has_element?(view, "#oai-endpoint-notice")
    end

    test "shows the machine endpoint that harvesters should use", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/oai")

      assert html =~ "/api/oai"
      assert has_element?(view, "#oai-api-endpoint")
    end

    test "defaults to the Identify verb", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/oai")

      assert has_element?(view, "#oai-identify")
      assert html =~ "Repository Information"
      assert html =~ "protocolVersion" or html =~ "2.0"
    end

    test "renders the verb selector", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/oai")

      assert has_element?(view, "#oai-verb-select")

      for verb <- ~w(Identify ListMetadataFormats ListSets ListIdentifiers ListRecords) do
        assert html =~ verb
      end
    end
  end

  describe "verb selection" do
    test "ListMetadataFormats shows the oai_dc format", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/oai?oai_verb=ListMetadataFormats")

      assert has_element?(view, "#oai-formats")
      assert html =~ "oai_dc"
    end

    test "ListSets shows communities and collections", %{conn: conn} do
      {community, collection} = create_collection()

      {:ok, view, html} = live(conn, ~p"/oai?oai_verb=ListSets")

      assert has_element?(view, "#oai-sets")
      assert html =~ community.name
      assert html =~ collection.name
    end

    test "ListRecords renders record metadata", %{conn: conn} do
      {_, collection} = create_collection()
      published_item(collection.id, %{"title" => "A Distinctive Thesis Title"})

      {:ok, view, html} = live(conn, ~p"/oai?oai_verb=ListRecords")

      assert has_element?(view, "#oai-records")
      assert html =~ "A Distinctive Thesis Title"
      assert html =~ "dc:title"
    end

    test "ListIdentifiers renders the record identifiers", %{conn: conn} do
      {_, collection} = create_collection()
      published_item(collection.id)

      {:ok, view, html} = live(conn, ~p"/oai?oai_verb=ListIdentifiers")

      assert has_element?(view, "#oai-identifiers")
      assert html =~ "oai:"
    end

    test "changing the verb re-renders the page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/oai")

      html =
        view
        |> form("#oai-verb-form", %{"verb" => "ListMetadataFormats"})
        |> render_change()

      assert html =~ "oai_dc"
    end

    test "the verb selector is inside a form so phx-change fires", %{conn: conn} do
      # LiveView binds phx-change to the *form*, not to a bare <select>. A
      # select outside a form never triggers the event, so the page silently
      # stopped responding to the dropdown.
      {:ok, view, _html} = live(conn, ~p"/oai")

      assert has_element?(view, "#oai-verb-form[phx-change=change_verb]")
      assert has_element?(view, "#oai-verb-select[name=verb]")
    end

    test "changing the verb through the form switches the view", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/oai")

      html =
        view
        |> form("#oai-verb-form", %{"verb" => "ListMetadataFormats"})
        |> render_change()

      assert html =~ "oai_dc"
      assert has_element?(view, "#oai-formats")
    end
  end

  describe "record filtering" do
    test "the set selector filters records", %{conn: conn} do
      {_, collection} = create_collection()
      published_item(collection.id, %{"title" => "Inside The Collection"})

      {:ok, view, html} = live(conn, ~p"/oai?oai_verb=ListRecords&set=col_#{collection.id}")

      assert html =~ "Inside The Collection"
      assert has_element?(view, "#oai-set-select")
    end
  end

  describe "the raw XML panel" do
    test "shows the XML the machine endpoint returns", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/oai")

      assert has_element?(view, "#oai-raw-xml")
      assert html =~ "OAI-PMH"
    end

    test "the Raw XML link carries the current verb", %{conn: conn} do
      # Without a verb the machine endpoint answers `badVerb`, so the link must
      # always include it.
      {:ok, view, _html} = live(conn, ~p"/oai?oai_verb=ListSets")

      href =
        view
        |> element(~s{a[href*="/api/oai"]})
        |> render()

      assert href =~ "verb=ListSets"
    end

    test "the Raw XML link carries metadataPrefix and the set filter", %{conn: conn} do
      {_, collection} = create_collection()

      {:ok, view, _html} =
        live(conn, ~p"/oai?oai_verb=ListRecords&set=col_#{collection.id}")

      href =
        view
        |> element(~s{a[href*="/api/oai"]})
        |> render()

      assert href =~ "verb=ListRecords"
      assert href =~ "metadataPrefix=oai_dc"
      assert href =~ "set=col_"
    end
  end

  describe "GetRecord" do
    test "renders the identifier form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/oai?oai_verb=GetRecord")

      assert has_element?(view, "#oai-get-record")
      assert has_element?(view, "#oai-identifier-input[name=identifier]")
    end

    test "fetches a record by its OAI identifier", %{conn: conn} do
      {_, collection} = create_collection()
      item = published_item(collection.id, %{"title" => "A Fetched Thesis"})

      identifier = "oai:kiroku.ac.id:#{item.id}"

      {:ok, view, _html} = live(conn, ~p"/oai?oai_verb=GetRecord")

      html =
        view
        |> form("#oai-get-record-form", %{"identifier" => identifier})
        |> render_submit()

      assert html =~ "A Fetched Thesis"
      assert has_element?(view, "#oai-get-record-result")
    end

    test "reports an unknown identifier", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/oai?oai_verb=GetRecord")

      html =
        view
        |> form("#oai-get-record-form", %{"identifier" => "oai:kiroku.ac.id:not-a-uuid"})
        |> render_submit()

      assert html =~ "No record matches that identifier."
      assert has_element?(view, "#oai-get-record-error")
    end

    test "does not return unpublished records", %{conn: conn} do
      {_, collection} = create_collection()
      item = published_item(collection.id, %{"title" => "Still A Draft"})

      {:ok, _item} =
        Repository.update_item(item, %{"status" => "draft", "title" => "Still A Draft"})

      {:ok, view, _html} = live(conn, ~p"/oai?oai_verb=GetRecord")

      html =
        view
        |> form("#oai-get-record-form", %{"identifier" => "oai:kiroku.ac.id:#{item.id}"})
        |> render_submit()

      refute html =~ "Still A Draft"
      assert has_element?(view, "#oai-get-record-error")
    end
  end

  describe "legacy /oai requests" do
    test "redirect OAI-PMH requests to /api/oai", %{conn: conn} do
      conn = get(conn, "/oai?verb=Identify")

      assert redirected_to(conn) == "/api/oai?verb=Identify"
    end

    test "redirect ListRecords requests, preserving the arguments", %{conn: conn} do
      conn = get(conn, "/oai?verb=ListRecords&metadataPrefix=oai_dc")

      assert redirected_to(conn) == "/api/oai?verb=ListRecords&metadataPrefix=oai_dc"
    end

    test "redirect resumptionToken requests", %{conn: conn} do
      conn = get(conn, "/oai?verb=ListRecords&resumptionToken=abc123")

      assert redirected_to(conn) == "/api/oai?verb=ListRecords&resumptionToken=abc123"
    end

    test "a bare /oai request is not redirected", %{conn: conn} do
      conn = get(conn, "/oai")

      assert conn.status == 200
      assert get_resp_header(conn, "location") == []
    end

    test "the UI's own browsing parameters are not redirected", %{conn: conn} do
      conn = get(conn, "/oai?oai_verb=ListRecords")

      assert conn.status == 200
      assert get_resp_header(conn, "location") == []
    end
  end

  describe "the /api/oai machine endpoint" do
    test "serves XML with an explicit UTF-8 charset", %{conn: conn} do
      conn = get(conn, "/api/oai?verb=Identify")

      assert response(conn, 200) =~ "<Identify>"
      assert get_resp_header(conn, "content-type") == ["text/xml; charset=utf-8"]
    end

    test "accepts an explicit text/xml Accept header", %{conn: conn} do
      conn =
        conn
        |> put_req_header("accept", "text/xml")
        |> get("/api/oai?verb=Identify")

      assert response(conn, 200) =~ "<Identify>"
    end

    test "never returns HTML", %{conn: conn} do
      conn = get(conn, "/api/oai?verb=Identify")

      refute response(conn, 200) =~ "<html"
    end
  end
end
