defmodule KirokuWeb.Router do
  use KirokuWeb, :router

  import KirokuWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {KirokuWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # ── Public routes (no auth required) ──────────────────────────────────────────

  scope "/", KirokuWeb do
    pipe_through :browser

    get "/", PageController, :home

    # Repository browsing
    get "/communities", CommunityController, :index
    get "/communities/:handle", CommunityController, :show
    get "/collections/:handle", CollectionController, :show
    get "/items/:handle", ItemController, :show

    # Bitstream file access
    get "/items/:item_id/bitstreams/:id", BitstreamController, :show

    # Search
    get "/search", SearchController, :index

    # OAI-PMH endpoint
    get "/oai", OaiController, :index
  end

  # ── Auth routes (guest only) ───────────────────────────────────────────────────

  scope "/", KirokuWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    live_session :guest,
      on_mount: [{KirokuWeb.UserAuth, :redirect_if_user_is_authenticated}] do
      live "/users/register", UserRegistrationLive, :new
      live "/users/log_in", UserSessionLive, :new
      live "/users/reset_password", UserResetPasswordLive, :new
      live "/users/reset_password/:token", UserResetPasswordLive, :edit
    end
  end

  # ── Authenticated routes ───────────────────────────────────────────────────────

  scope "/", KirokuWeb do
    pipe_through [:browser, :require_authenticated_user]

    # Session delete still uses a controller (needs POST + redirect)
    delete "/users/log_out", UserSessionController, :delete

    live_session :authenticated,
      on_mount: [{KirokuWeb.UserAuth, :ensure_authenticated}] do
      # Email confirmation
      live "/users/confirm", UserConfirmationLive, :new
      live "/users/confirm/:token", UserConfirmationLive, :edit

      # User settings
      live "/users/settings", UserSettingsLive, :edit
      live "/users/settings/confirm_email/:token", UserSettingsLive, :confirm_email

      # Submitter: own items
      live "/my/items", MyItemLive.Index, :index
      live "/my/items/new", MyItemLive.Index, :new
      live "/my/items/:id/edit", MyItemLive.Index, :edit

      # Submission form
      live "/submit", SubmissionLive.New, :new
    end
  end

  # ── Staff / Admin routes ───────────────────────────────────────────────────────

  scope "/admin", KirokuWeb.Admin do
    pipe_through [:browser, :require_authenticated_user]

    live_session :admin,
      on_mount: [{KirokuWeb.UserAuth, :ensure_authenticated}] do
      # Dashboard
      live "/", DashboardLive, :index

      # Community management
      live "/communities", CommunityLive.Index, :index
      live "/communities/new", CommunityLive.Index, :new
      live "/communities/:id/edit", CommunityLive.Index, :edit
      live "/communities/:id", CommunityLive.Show, :show

      # Collection management
      live "/collections", CollectionLive.Index, :index
      live "/collections/new", CollectionLive.Index, :new
      live "/collections/:id/edit", CollectionLive.Index, :edit
      live "/collections/:id", CollectionLive.Show, :show

      # Item review
      live "/items", ItemLive.Index, :index
      live "/items/:id", ItemLive.Show, :show
      live "/items/:id/review", ItemLive.Review, :review

      # User management
      live "/users", UserLive.Index, :index
      live "/users/:id", UserLive.Show, :show
      live "/users/:id/edit", UserLive.Show, :edit

      # Storage settings
      live "/settings", SettingsLive, :index
    end
  end

  # ── OAI-PMH API ───────────────────────────────────────────────────────────────

  scope "/api", KirokuWeb.Api, as: :api do
    pipe_through :api

    get "/oai", OaiController, :index
  end

  # ── Dev tools ─────────────────────────────────────────────────────────────────

  if Application.compile_env(:kiroku, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: KirokuWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
