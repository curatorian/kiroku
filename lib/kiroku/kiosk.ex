defmodule Kiroku.Kiosk do
  @moduledoc """
  Kiosk (fleet) configuration and device status.

  State is a combination of:
    * the presented device token (`token_type: :device`) — deleted/rotated
      tokens read as *revoked* (the endpoint 401s), an unapproved device reads
      *needs_reverify*
    * the global maintenance flag in Settings — reads *maintenance*
    * otherwise *active*

  Reader/visitor policies (allow_save, allow_print, watermark, idle timers)
  live in `Kiroku.Settings` so admins can change them without a deploy.
  """

  alias Kiroku.Settings

  # Settings rows store values as text — structured blobs are JSON-encoded.
  @policies_key "kiosk_policies"
  @maintenance_key "kiosk_maintenance"
  @announcement_key "kiosk_announcement"
  @contact_key "kiosk_contact"

  @defaults %{
    "allow_save" => true,
    "allow_print" => true,
    "allow_copy" => false,
    "watermark" => false,
    "idle_seconds" => 600,
    "reader_idle_seconds" => 900,
    "page_size_default" => 20
  }

  @type state :: :active | :needs_reverify | :maintenance

  # ── Status assembly ───────────────────────────────────────────────────────

  @doc """
  Assembles the kiosk status payload for a presented API token.

  `api_token` is the `Kiroku.ApiToken` resolved by the auth plug.
  Returns the map understood by the kiosk's `mapKioskStatus`:

      %{state: "active", tier: "kiosk", server_time: iso8601,
        announcement: ..., contact: ..., policies: %{...}}
  """
  def status(api_token) do
    tier = if api_token && api_token.token_type == :device, do: "kiosk", else: "public"

    %{
      state: state(api_token),
      tier: tier,
      server_time: DateTime.utc_now()
    }
    |> Map.merge(client_config())
  end

  defp state(api_token) do
    cond do
      maintenance_enabled?() ->
        "maintenance"

      (api_token && api_token.token_type == :device) and is_nil(api_token.approved_at) ->
        "needs_reverify"

      true ->
        "active"
    end
  end

  # ── Client-facing config (policies, announcement, contact) ────────────────

  @doc """
  Returns the client-facing config block shared by all kiosk status responses:
  `announcement`, `contact` and `policies`.
  """
  def client_config do
    %{
      announcement: get_raw(@announcement_key),
      contact: get_raw(@contact_key),
      policies: policies()
    }
  end

  @doc "User-visible policies with defaults filled in."
  def policies do
    Map.merge(@defaults, get_service_map(@policies_key) || %{})
    |> Enum.filter(fn {k, _} -> k in Map.keys(@defaults) end)
    |> Map.new()
  end

  # ── Maintenance ───────────────────────────────────────────────────────────

  @doc "Global maintenance flag: `%{\"enabled\": true/false, \"message\": \"...\"}`."
  def maintenance do
    case get_service_map(@maintenance_key) do
      nil -> %{"enabled" => false, "message" => nil}
      map -> %{"enabled" => !!map["enabled"], "message" => map["message"]}
    end
  end

  def maintenance_enabled?, do: maintenance()["enabled"]

  def put_maintenance(enabled, message) when is_boolean(enabled) do
    put_json(@maintenance_key, %{"enabled" => enabled, "message" => message})
  end

  def put_announcement(text), do: Settings.put(@announcement_key, text)

  def put_contact(text), do: Settings.put(@contact_key, text)

  def put_policies(policies) when is_map(policies) do
    put_json(@policies_key, Map.take(policies, Map.keys(@defaults)))
  end

  # ── Storage helpers (Settings values are strings) ─────────────────────────

  defp get_raw(key), do: Settings.get(key)

  defp get_service_map(key) do
    case Settings.get(key) do
      nil -> nil
      "" -> nil
      raw when is_binary(raw) -> decode_json(raw)
      _ -> nil
    end
  end

  defp put_json(key, map), do: Settings.put(key, Jason.encode!(map))

  defp decode_json(raw) do
    case Jason.decode(raw) do
      {:ok, map} when is_map(map) -> map
      _ -> nil
    end
  end
end
