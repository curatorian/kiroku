defmodule KirokuWeb.Api.OaiController do
  use KirokuWeb, :controller

  # Delegate to the main OAI controller logic
  defdelegate index(conn, params), to: KirokuWeb.OaiController
end
