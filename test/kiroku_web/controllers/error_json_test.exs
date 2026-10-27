defmodule KirokuWeb.ErrorJSONTest do
  use KirokuWeb.ConnCase, async: true

  test "renders 404 with the uniform envelope" do
    assert KirokuWeb.ErrorJSON.render("404.json", %{}) == %{
             error: "not_found",
             message: "Not Found"
           }
  end

  test "renders 500 with the uniform envelope" do
    assert KirokuWeb.ErrorJSON.render("500.json", %{}) ==
             %{error: "internal_error", message: "Internal Server Error"}
  end
end
