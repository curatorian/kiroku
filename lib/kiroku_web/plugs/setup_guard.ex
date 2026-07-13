defmodule KirokuWeb.Plugs.SetupGuard do
  @moduledoc """
  Locks the application to the first-run setup wizard until onboarding is
  complete.

  When `Kiroku.Onboarding.needs_setup?/0` is true, every browser request that
  is not destined for the wizard itself is redirected to `/setup`. Static
  assets are served by `Plug.Static` at the endpoint (before the router), so
  they never reach this plug. Once setup is complete, all traffic flows through
  normally.
  """

  import Phoenix.Controller, only: [redirect: 2]
  import Plug.Conn

  @doc false
  def init(opts), do: opts

  @doc false
  def call(conn, _opts) do
    if Kiroku.Onboarding.needs_setup?() do
      if allowed_path?(conn.request_path) do
        conn
      else
        conn |> redirect(to: "/setup") |> halt()
      end
    else
      conn
    end
  end

  defp allowed_path?(path) do
    # Public crawler/harvester endpoints must always respond — redirecting
    # them to /setup would confuse crawlers and break harvesting.
    path == "/setup" or
      String.starts_with?(path, "/setup/") or
      String.starts_with?(path, "/phoenix") or
      String.starts_with?(path, "/dev") or
      path in ["/robots.txt", "/sitemap.xml", "/oai", "/health"]
  end
end
