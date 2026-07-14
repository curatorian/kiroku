defmodule KirokuWeb.Plugs.SetupGuardTest do
  use KirokuWeb.ConnCase, async: false

  alias Kiroku.Onboarding

  # Manipulates the global :persistent_term cache, so cannot run async.
  setup do
    Onboarding.force_setup_state(false)
    on_exit(fn -> Onboarding.force_setup_state(true) end)
    :ok
  end

  describe "when setup is not complete" do
    test "redirects the homepage to /setup" do
      conn = get(build_conn(), ~p"/")
      assert redirected_to(conn) == ~p"/setup"
    end

    test "allows /setup through" do
      conn = get(build_conn(), ~p"/setup")
      # 200 means the wizard LiveView rendered (not redirected)
      assert html_response(conn, 200)
    end

    test "redirects other authenticated routes to /setup" do
      conn = get(build_conn(), ~p"/users/log_in")
      assert redirected_to(conn) == ~p"/setup"
    end
  end

  describe "when setup is complete" do
    test "lets the homepage through" do
      Onboarding.force_setup_state(true)
      conn = get(build_conn(), ~p"/")
      assert html_response(conn, 200) =~ "Every work recorded"
    end
  end
end
