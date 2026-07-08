defmodule KirokuWeb.UserAuthPausController do
  use KirokuWeb, :controller

  alias Kiroku.Accounts
  alias KirokuWeb.UserAuth
  require Logger

  @authorization_url "https://paus.unpad.ac.id/oauth"
  @access_token_url "https://paus.unpad.ac.id/oauth/access-token"
  @api_url "https://paus.unpad.ac.id/api"
  @scope "user.basic"

  def request(conn, _params) do
    state = generate_state()
    conn = put_session(conn, :paus_oauth_state, state)

    conn
    |> redirect(external: authorization_url(state))
  end

  def callback(conn, _params) do
    conn = fetch_query_params(conn)
    params = conn.params
    stored_state = get_session(conn, :paus_oauth_state)

    cond do
      params["error"] ->
        error_redirect(conn, params["error_description"] || params["error"])

      params["state"] != stored_state ->
        error_redirect(conn, "Invalid state parameter. Please try again.")

      params["code"] ->
        handle_code(conn, params["code"])

      true ->
        error_redirect(conn, "Invalid OAuth callback parameters.")
    end
  end

  defp handle_code(conn, code) do
    with {:ok, token} <- exchange_code_for_token(code),
         {:ok, paus_profile} <- fetch_paus_profile(token),
         {:ok, user} <- find_or_create_user(paus_profile) do
      conn
      |> delete_session(:paus_oauth_state)
      |> put_flash(:info, "Selamat datang, #{user.display_name || user.email}!")
      |> UserAuth.log_in_user(user)
    else
      {:error, reason} ->
        error_redirect(conn, reason)
    end
  end

  defp find_or_create_user(%{"email" => email} = paus_profile) when is_binary(email) do
    attrs = oauth_user_attrs(paus_profile)

    case Accounts.get_user_by_email(email) do
      nil ->
        # New user → create then assign :internal role
        with {:ok, user} <- Accounts.create_user_from_oauth(attrs),
             {:ok, user} <- Accounts.assign_internal_role(user) do
          {:ok, user}
        end

      %Kiroku.Accounts.User{user_type: :submitter} = user ->
        # Default role → upgrade to :internal (PAuS = verified academic member)
        Accounts.assign_internal_role(user)

      user ->
        # Has an assigned role (internal/reviewer/admin/superadmin) → leave as-is
        {:ok, user}
    end
  end

  defp find_or_create_user(_), do: {:error, "PAuS did not return an email address."}

  defp oauth_user_attrs(paus_profile) do
    accounts = Map.get(paus_profile, "accounts", [])
    account = Enum.find(accounts, &(&1["is_active"] == true)) || List.first(accounts) || %{}

    %{
      "email" => Map.get(paus_profile, "email"),
      "display_name" =>
        Map.get(paus_profile, "name") || Map.get(paus_profile, "username") ||
          Map.get(paus_profile, "email"),
      "identifier" => Map.get(account, "number") || Map.get(account, "identifier"),
      "faculty" => Map.get(account, "faculty_name") || Map.get(account, "faculty"),
      "department" => Map.get(account, "unit_name") || Map.get(account, "unit"),
      "avatar_url" => Map.get(paus_profile, "image_url")
    }
  end

  defp exchange_code_for_token(code) do
    config = paus_config()

    params = %{
      grant_type: "authorization_code",
      client_id: config.client_id,
      client_secret: config.client_secret,
      redirect_uri: config.redirect_uri,
      code: code
    }

    headers = [
      {"content-type", "application/x-www-form-urlencoded"},
      {"user-agent", "Kiroku PAuS Client/1.0"}
    ]

    body = URI.encode_query(params)

    case Req.post(@access_token_url, body: body, headers: headers, receive_timeout: 30_000) do
      {:ok, %Req.Response{status: 200, body: %{"access_token" => access_token} = body}} ->
        {:ok, build_token(body, access_token)}

      {:ok, %Req.Response{status: 200, body: body}} ->
        case parse_body(body) do
          {:ok, %{"access_token" => access_token} = body} ->
            {:ok, build_token(body, access_token)}

          {:ok, %{"error" => error}} ->
            {:error, error}

          _ ->
            {:error, "Unexpected token response from PAuS."}
        end

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, "PAuS token exchange failed (#{status}): #{inspect(body)}"}

      {:error, reason} ->
        {:error, "PAuS token exchange request failed: #{inspect(reason)}"}
    end
  end

  defp fetch_paus_profile(token) do
    url = "#{@api_url}/accounts?access_token=#{token.access_token}"
    headers = [{"accept", "application/json"}, {"user-agent", "Kiroku PAuS Client/1.0"}]

    case Req.get(url, headers: headers, receive_timeout: 30_000) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        case parse_body(body) do
          {:ok, profile} when is_map(profile) -> {:ok, profile}
          _ -> {:error, "Failed to decode PAuS profile."}
        end

      {:ok, %Req.Response{status: 401}} ->
        {:error, "Unauthorized when fetching PAuS profile."}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, "PAuS profile request failed (#{status}): #{inspect(body)}"}

      {:error, reason} ->
        {:error, "PAuS profile request failed: #{inspect(reason)}"}
    end
  end

  defp parse_body(body) when is_map(body), do: {:ok, body}
  defp parse_body(body) when is_binary(body), do: Jason.decode(body)
  defp parse_body(_), do: {:error, :invalid_body}

  defp build_token(body, access_token) do
    expires_in = body["expires_in"]
    expires_in_int = if is_binary(expires_in), do: String.to_integer(expires_in), else: expires_in

    %{
      access_token: access_token,
      refresh_token: Map.get(body, "refresh_token"),
      token_type: Map.get(body, "token_type", "Bearer"),
      expires_at:
        if(is_integer(expires_in_int), do: :os.system_time(:second) + expires_in_int, else: nil)
    }
  end

  defp authorization_url(state) do
    config = paus_config()

    query =
      URI.encode_query(%{
        response_type: "code",
        client_id: config.client_id,
        redirect_uri: config.redirect_uri,
        scope: @scope,
        state: state
      })

    "#{@authorization_url}?#{query}"
  end

  defp paus_config do
    %{
      client_id: require_env!("KIROKU_PAUS_CLIENT_ID"),
      client_secret: require_env!("KIROKU_PAUS_CLIENT_SECRET"),
      redirect_uri: require_env!("KIROKU_PAUS_REDIRECT_URI")
    }
  end

  defp require_env!(key) do
    System.get_env(key) ||
      raise("environment variable #{key} is missing. Set it in .env or the runtime environment.")
  end

  defp error_redirect(conn, message) do
    conn
    |> put_flash(:error, "PAuS authentication failed: #{message}")
    |> redirect(to: ~p"/users/log_in")
  end

  defp generate_state do
    :crypto.strong_rand_bytes(32)
    |> Base.url_encode64(padding: false)
  end
end
