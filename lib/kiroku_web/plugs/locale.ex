defmodule KirokuWeb.Plugs.Locale do
  @moduledoc """
  Plug and LiveView on_mount hook for locale management.

  Reads `?locale=` from query params (takes precedence), falls back to the
  session, then defaults to "id". Stores the resolved locale in the session and
  sets it on the current Gettext backend process.

  Usage in LiveViews is handled automatically via `on_mount :set_locale` which
  is wired up in `KirokuWeb.live_view/0`.
  """

  import Plug.Conn

  @supported ~w(id en)
  @default "id"

  # ── Plug ─────────────────────────────────────────────────────────────────────

  def init(opts), do: opts

  def call(conn, _opts) do
    locale =
      (conn.params["locale"] || get_session(conn, :locale) || @default)
      |> then(&if &1 in @supported, do: &1, else: @default)

    Gettext.put_locale(KirokuWeb.Gettext, locale)
    put_session(conn, :locale, locale)
  end

  # ── LiveView on_mount ─────────────────────────────────────────────────────────

  def on_mount(:set_locale, params, session, socket) do
    locale =
      (params["locale"] || Map.get(session, "locale") || @default)
      |> then(&if &1 in @supported, do: &1, else: @default)

    Gettext.put_locale(KirokuWeb.Gettext, locale)
    {:cont, Phoenix.Component.assign(socket, :locale, locale)}
  end
end
