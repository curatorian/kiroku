defmodule KirokuWeb.Api.V1.CommunityHierarchyApiTest do
  use KirokuWeb.ConnCase, async: true

  alias Kiroku.{Accounts, ApiTokens, Repository}

  defp create_user do
    {:ok, user} =
      Accounts.register_user(%{
        "email" => "hier-#{System.unique_integer([:positive])}@example.test",
        "password" => "password123456"
      })

    user
  end

  setup do
    user = create_user()
    {:ok, raw, _} = ApiTokens.create_token(user, "hier-token")

    {:ok, root} =
      Repository.create_community(%{
        "name" => "Root Unkris",
        "handle" => "root-#{System.unique_integer([:positive])}"
      })

    {:ok, child} =
      Repository.create_community(%{
        "name" => "Fakultas Teknik",
        "handle" => "ft-#{System.unique_integer([:positive])}",
        "parent_community_id" => root.id
      })

    %{raw_token: raw, root: root, child: child}
  end

  defp authed_conn(raw) do
    build_conn() |> put_req_header("authorization", "Bearer #{raw}")
  end

  describe "hierarchy" do
    test "list payload carries parent_community_id (nil for roots)", %{
      raw_token: raw,
      root: root,
      child: child
    } do
      conn = authed_conn(raw) |> get(~p"/api/v1/communities")
      data = json_response(conn, 200)["data"]

      child_entry = Enum.find(data, &(&1["id"] == child.id))
      assert child_entry
      assert child_entry["parent_community_id"] == root.id

      root_entry = Enum.find(data, &(&1["id"] == root.id))
      assert root_entry["parent_community_id"] == nil
    end

    test "subcommunities route returns direct children with X-Total-Count", %{
      raw_token: raw,
      root: root,
      child: child
    } do
      conn = authed_conn(raw) |> get(~p"/api/v1/communities/#{root.id}/subcommunities")

      assert ["1"] == get_resp_header(conn, "x-total-count")
      data = json_response(conn, 200)["data"]
      assert [%{"id" => child_id}] = data
      assert child_id == child.id
    end

    test "subcommunities route accepts the parent handle", %{
      raw_token: raw,
      root: root,
      child: child
    } do
      conn = authed_conn(raw) |> get(~p"/api/v1/communities/#{root.handle}/subcommunities")

      data = json_response(conn, 200)["data"]
      assert [%{"id" => child_id}] = data
      assert child_id == child.id
    end
  end
end
