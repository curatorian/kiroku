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
    plug KirokuWeb.Plugs.Locale
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # ── Public routes (no auth required) ──────────────────────────────────────────

  scope "/", KirokuWeb do
    pipe_through :browser

    get "/", PageController, :home

    # Handle resolver (DSpace legacy URLs)
    get "/handle/*path", HandleController, :show

    # Citation download — /citation/:id/format/:format
    get "/citation/:id/format/:format", CitationController, :show

    # OAI-PMH endpoint
    get "/oai", OaiController, :index

    # Bitstream file access
    get "/items/:item_id/bitstreams/:id", BitstreamController, :show

    # Public repository browsing (LiveView, optional auth)
    live_session :public,
      on_mount: [{KirokuWeb.UserAuth, :mount_current_user}] do
      live "/browse", BrowseLive, :index
      live "/search", SearchLive, :index
      live "/communities", CommunityLive.Index, :index
      live "/communities/:handle", CommunityLive.Show, :show
      live "/collections/:handle", CollectionLive.Show, :show
      live "/items/:handle", ItemLive.Show, :show
    end
  end

  # ── REST API v1 ────────────────────────────────────────────────────────────────

  scope "/api/v1", KirokuWeb.Api.V1 do
    pipe_through :api

    resources "/communities", CommunityController, only: [:index, :show]
    resources "/collections", CollectionController, only: [:index, :show]

    resources "/items", ItemController, only: [:index, :show] do
      get "/bitstreams", ItemController, :bitstreams, as: :bitstreams
    end
  end

  # ── Auth routes (guest only) ───────────────────────────────────────────────────

  scope "/", KirokuWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    post "/users/log_in", UserSessionController, :create

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
      live "/submit/:id/edit", SubmissionLive.Edit, :edit
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
      live "/items/new", ItemLive.Index, :new
      live "/items/:id", ItemLive.Show, :show
      live "/items/:id/review", ItemLive.Review, :review

      # User management
      live "/users", UserLive.Index, :index
      live "/users/new", UserLive.Index, :new
      live "/users/:id", UserLive.Show, :show
      live "/users/:id/edit", UserLive.Show, :edit
      live "/users/:id/password", UserLive.Show, :password
      live "/users/:id/policies/new", UserLive.Show, :new_policy
      live "/users/:id/policies/:policy_id/edit", UserLive.Show, :edit_policy

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
