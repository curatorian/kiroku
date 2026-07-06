defmodule Kiroku.LegacyRepo.Inspector do
  @moduledoc """
  Utilities for inspecting and testing the MSSQL LegacyRepo connection.
  Provides connection validation and diagnostic information.
  """

  alias Kiroku.LegacyRepo

  @doc """
  Tests the MSSQL connection and returns connection status information.

  Returns `:ok` with connection info map on successful connection, or
  `{:error, reason}` on connection failure.

  ## Examples

      iex> LegacyRepo.Inspector.test_connection()
      {:ok, %{hostname: "localhost", database: "legacy_db", version: "15.0.2000"}}

      iex> LegacyRepo.Inspector.test_connection()
      {:error, :connection_failed}
  """
  def test_connection do
    case ensure_repo_started() do
      :ok ->
        perform_connection_test()

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Returns the current LegacyRepo configuration.
  Useful for displaying connection details without actually connecting.

  ## Examples

      iex> LegacyRepo.Inspector.get_config()
      %{hostname: "localhost", database: "legacy_db", port: 1433}
  """
  def get_config do
    config = LegacyRepo.config()

    %{
      hostname: Keyword.get(config, :hostname),
      database: Keyword.get(config, :database),
      port: Keyword.get(config, :port, 1433),
      username: Keyword.get(config, :username),
      pool_size: Keyword.get(config, :pool_size, 2),
      configured?: is_configured?(config)
    }
  end

  @doc """
  Returns a human-readable connection status message.

  ## Examples

      iex> LegacyRepo.Inspector.status_message()
      "Connected to MSSQL database 'legacy_db' on localhost:1433"

      iex> LegacyRepo.Inspector.status_message()
      "Not configured: Missing database credentials"
  """
  def status_message do
    config = get_config()

    cond do
      !config.configured? ->
        "Not configured: Missing database credentials"

      true ->
        case test_connection() do
          {:ok, %{hostname: hostname, database: database, port: port}} ->
            "Connected to MSSQL database '#{database}' on #{hostname}:#{port}"

          {:error, :repo_not_started} ->
            "Connection not established: LegacyRepo not started"

          {:error, :connection_failed} ->
            "Connection failed: Unable to reach MSSQL server"

          {:error, reason} ->
            "Connection error: #{inspect(reason)}"
        end
    end
  end

  def ensure_repo_started do
    case LegacyRepo.start_link() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, _reason} -> {:error, :repo_not_started}
    end
  end

  def perform_connection_test do
    config = get_config()

    try do
      query = "SELECT @@VERSION as version"
      result = Ecto.Adapters.SQL.query!(LegacyRepo, query, [])

      case result do
        %{rows: [[version_string]]} ->
          {:ok,
           %{
             hostname: config.hostname,
             database: config.database,
             port: config.port,
             version: extract_version(version_string),
             version_string: version_string,
             connected_at: DateTime.utc_now()
           }}

        _ ->
          {:error, :unexpected_response}
      end
    rescue
      _e in [DBConnection.ConnectionError, Postgrex.Error, Tds.Error] ->
        {:error, :connection_failed}

      e ->
        {:error, e}
    end
  end

  @doc """
  Checks if the configuration has all required fields.
  """
  def is_configured?(config) do
    Keyword.get(config, :hostname) != nil and
      Keyword.get(config, :database) != nil and
      Keyword.get(config, :username) != nil and
      Keyword.get(config, :password) != nil
  end

  @doc """
  Extracts the first line from a version string.
  """
  def extract_version(version_string) when is_binary(version_string) do
    version_string
    |> String.split("\n")
    |> Enum.at(0)
    |> String.trim()
  end

  def extract_version(_), do: "Unknown"
end
