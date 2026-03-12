defmodule KirokuWeb.PageController do
  use KirokuWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
