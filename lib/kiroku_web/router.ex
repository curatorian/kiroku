defmodule KirokuWeb.Router do
  use KirokuWeb, :router

  use AshAuthentication.Phoenix.Router

  import AshAuthentication.Plug.Helpers

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {KirokuWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :load_from_session
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :load_from_bearer
    plug :set_actor, :user
  end

  pipeline :xml do
    plug :accepts, ["xml", "json"]
  end

  pipeline :require_auth do
    plug KirokuWeb.Plugs.RequireAuth
  end

  pipeline :require_admin do
    plug KirokuWeb.Plugs.RequireAdmin
  end

  # ── Authentication routes (magic link) ──────────────────────────────────────
  scope "/", KirokuWeb do
    pipe_through :browser

    auth_routes AuthController, Kiroku.Accounts.User, path: "/auth"
    sign_out_route AuthController

    sign_in_route register_path: "/register",
                  reset_path: "/reset",
                  auth_routes_prefix: "/auth",
                  on_mount: [{KirokuWeb.LiveUserAuth, :live_no_user}],
                  overrides: [
                    KirokuWeb.AuthOverrides,
                    Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI
                  ]

    reset_route auth_routes_prefix: "/auth",
                overrides: [
                  KirokuWeb.AuthOverrides,
                  Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI
                ]

    confirm_route Kiroku.Accounts.User, :confirm_new_user,
      auth_routes_prefix: "/auth",
      overrides: [KirokuWeb.AuthOverrides, Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI]

    magic_sign_in_route(Kiroku.Accounts.User, :magic_link,
      auth_routes_prefix: "/auth",
      overrides: [KirokuWeb.AuthOverrides, Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI]
    )
  end

  # ── Public routes ───────────────────────────────────────────────────────────
  scope "/", KirokuWeb do
    pipe_through :browser

    get "/", PageController, :home

    # Handle resolver (DSpace-compatible)
    get "/handle/:prefix/:suffix", HandleController, :resolve
    get "/handle/:prefix/:suffix/statistics", HandleController, :statistics

    # Bitstream download routes
    get "/bitstream/handle/:prefix/:suffix/:filename",
        BitstreamController,
        :download_by_handle_filename

    get "/bitstream/handle/:prefix/:suffix/:sequence/:filename",
        BitstreamController,
        :download_by_handle

    get "/bitstreams/:id/download", BitstreamController, :download

    # Citation export
    get "/items/:id/export.bib", CitationController, :bibtex
    get "/items/:id/export.ris", CitationController, :ris
    get "/items/:id/export.enw", CitationController, :endnote
  end

  # ── Public LiveView routes ──────────────────────────────────────────────────
  scope "/", KirokuWeb do
    pipe_through :browser

    ash_authentication_live_session :public_routes,
      on_mount: [{KirokuWeb.LiveUserAuth, :live_user_optional}] do
      live "/items/:id", ItemLive.Show
      live "/items/:id/full", ItemLive.ShowFull

      live "/communities", CommunityLive.Index
      live "/communities/:id", CommunityLive.Show

      live "/collections/:id", CollectionLive.Show

      live "/browse", BrowseLive.Index
      live "/browse/author", BrowseLive.Author
      live "/browse/title", BrowseLive.Title
      live "/browse/dateissued", BrowseLive.Date
      live "/browse/subject", BrowseLive.Subject

      live "/search", SearchLive.Index

      live "/statistics", StatisticsLive.Index
      live "/statistics/items/:id", StatisticsLive.Item
      live "/statistics/collections/:id", StatisticsLive.Collection

      live "/info/about", InfoLive.About
      live "/info/privacy", InfoLive.Privacy
      live "/info/help", InfoLive.Help
    end
  end

  # ── Authenticated routes ────────────────────────────────────────────────────
  scope "/", KirokuWeb do
    pipe_through [:browser, :require_auth]

    ash_authentication_live_session :authenticated_routes,
      on_mount: [{KirokuWeb.LiveUserAuth, :live_user_required}] do
      live "/mykiroku", MyKirokuLive.Dashboard
      live "/items/:id/edit", ItemLive.Edit
      live "/submit", SubmissionLive.SelectCollection
      live "/workspaceitems/:id", SubmissionLive.Workspace
      live "/workspaceitems/:id/edit", SubmissionLive.Edit
      live "/workflowitems/:id", WorkflowLive.Review
      live "/profile", ProfileLive.Show
      live "/profile/edit", ProfileLive.Edit
      live "/collections/:id/submit", SubmissionLive.New
    end
  end

  # ── Admin routes (AshAdmin + custom) ────────────────────────────────────────
  scope "/admin", KirokuWeb do
    pipe_through [:browser, :require_admin]

    ash_authentication_live_session :admin_routes,
      on_mount: [{KirokuWeb.LiveUserAuth, :live_user_required}] do
      live "/embargo", Admin.EmbargoLive.Index
      live "/batch-import", Admin.BatchImportLive.Index
    end
  end

  # ── OAI-PMH ────────────────────────────────────────────────────────────────
  scope "/server/oai", KirokuWeb do
    pipe_through :xml
    get "/request", OaiPmhController, :handle_request
  end

  scope "/oai", KirokuWeb do
    pipe_through :xml
    get "/request", OaiPmhController, :handle_request
  end

  # ── Dev routes ──────────────────────────────────────────────────────────────
  if Application.compile_env(:kiroku, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: KirokuWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  if Application.compile_env(:kiroku, :dev_routes) do
    import AshAdmin.Router

    scope "/admin" do
      pipe_through :browser

      ash_admin "/"
    end
  end
end
