defmodule KirokuWeb.Api.V1.ErrorEnvelopeTest do
  use KirokuWeb.ConnCase, async: true

  # Every non-2xx under /api/v1 must be application/json in the uniform
  # envelope — including framework-level 404s from unmatched routes.

  test "unmatched /api/v1 route returns the uniform JSON envelope" do
    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer whatever")
      |> get(~p"/api/v1/definitely-not-a-route")

    assert conn.status == 404
    content_type = get_resp_header(conn, "content-type") |> List.first()
    assert content_type |> String.starts_with?("application/json")
    assert json_response(conn, 404) == %{"error" => "not_found", "message" => "Not Found"}
  end

  test "missing token error uses the envelope" do
    conn = get(build_conn(), ~p"/api/v1/items")

    assert conn.status == 401
    assert %{"error" => "unauthorized", "message" => message} = json_response(conn, 401)
    assert message =~ "API token"
  end

  test "invalid list params return the envelope" do
    {:ok, user} =
      Kiroku.Accounts.register_user(%{
        "email" => "env-#{System.unique_integer([:positive])}@example.test",
        "password" => "password123456"
      })

    {:ok, raw, _} = Kiroku.ApiTokens.create_token(user, "env-token")

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{raw}")
      |> get(~p"/api/v1/items", year: "not-a-number")

    assert conn.status == 400
    assert %{"error" => "bad_request"} = json_response(conn, 400)
  end

  test "ErrorJSON covers framework templates" do
    assert KirokuWeb.ErrorJSON.render("400.json", %{}) == %{
             error: "bad_request",
             message: "Bad Request"
           }

    assert KirokuWeb.ErrorJSON.render("500.json", %{}) == %{
             error: "internal_error",
             message: "Internal Server Error"
           }
  end
end
