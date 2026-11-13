defmodule KirokuWeb.Plugs.RateLimitTest do
  use KirokuWeb.ConnCase, async: true

  alias KirokuWeb.Plugs.RateLimit

  test "allows requests up to the limit, then 429s", %{conn: conn} do
    opts =
      RateLimit.init(
        bucket: "rate-limit-test-#{System.unique_integer([:positive])}",
        limit: 2,
        period_ms: 60_000
      )

    conn1 = RateLimit.call(conn, opts)
    refute conn1.halted

    conn2 = RateLimit.call(conn1, opts)
    refute conn2.halted

    conn3 = RateLimit.call(conn2, opts)
    assert conn3.halted
    assert conn3.status == 429
  end

  test "keys are scoped per bucket" do
    period = 60_000

    exhausted =
      RateLimit.init(
        bucket: "rate-limit-a-#{System.unique_integer([:positive])}",
        limit: 1,
        period_ms: period
      )

    fresh =
      RateLimit.init(
        bucket: "rate-limit-b-#{System.unique_integer([:positive])}",
        limit: 1,
        period_ms: period
      )

    conn = RateLimit.call(build_conn(), exhausted)
    refute conn.halted

    conn = RateLimit.call(build_conn(), exhausted)
    assert conn.halted

    conn = RateLimit.call(build_conn(), fresh)
    refute conn.halted
  end

  test "check/3 returns :ok or {:deny, retry_after_ms}" do
    key = "rate-limit-check-#{System.unique_integer([:positive])}"

    assert RateLimit.check(key, 1, 60_000) == :ok
    assert {:deny, retry_after} = RateLimit.check(key, 1, 60_000)
    assert is_integer(retry_after)
  end
end
