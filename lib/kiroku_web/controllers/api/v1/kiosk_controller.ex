defmodule KirokuWeb.Api.V1.KioskController do
  @moduledoc """
  REST API v1 — kiosk device status (SPEC 6 gap 2).

  GET /api/v1/kiosks/status
  """
  use KirokuWeb, :controller

  alias Kiroku.Kiosk

  @doc """
  Returns the kiosk state for the presented token.

    * deleted/rotated token → handled upstream as a 401 (kiosk reads "revoked")
    * unapproved device token → state "needs_reverify"
    * maintenance flag on → state "maintenance"
    * otherwise "active"
  """
  def status(conn, _params) do
    json(conn, Kiosk.status(conn.assigns[:api_token]))
  end
end
