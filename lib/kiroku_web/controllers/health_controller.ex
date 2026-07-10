defmodule KirokuWeb.HealthController do
  use KirokuWeb, :controller

  def show(conn, _params) do
    json(conn, %{status: "ok"})
  end
end
