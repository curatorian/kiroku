# MSSQL Connection Inspection

This module provides utilities for inspecting and testing the MSSQL LegacyRepo connection before importing data.

## CLI Usage

### Check Connection Status

Test the MSSQL connection without performing any import:

```bash
mix kiroku.import_from_mssql --check-connection
```

This command will:

1. Display the current MSSQL configuration
2. Test the connection to the MSSQL server
3. Show detailed connection status and error messages if the connection fails
4. Exit with appropriate status codes (0 for success, 1 for failure)

Example successful output:

```
Checking MSSQL connection status…

Connection Configuration:
  • Hostname: localhost
  • Database: legacy_db
  • Port: 1433
  • Username: admin
  • Pool Size: 2

✅ Connection successful!
  • Server Version: Microsoft SQL Server 2019 (RTM-CU15-GDR) (KB4583462) - 15.0.4102.2 (X64)
  • Connected at: 2026-07-06 12:34:56.789012Z

The MSSQL database is accessible and ready for import.
```

Example failure output:

```
Checking MSSQL connection status…

Connection Configuration:
  • Hostname: localhost
  • Database: legacy_db
  • Port: 1433
  • Username: admin
  • Pool Size: 2

❌ Connection failed: Unable to reach MSSQL server.

This may be due to:
  • Network connectivity issues
  • Incorrect database credentials
  • Firewall blocking the connection
  • MSSQL server not running

Please check your configuration and try again.
```

### Before Importing

You can also check the connection as part of your regular import workflow:

```bash
# First check the connection
mix kiroku.import_from_mssql --check-connection

# Then proceed with import if connection is successful
mix kiroku.import_from_mssql --dry-run
mix kiroku.import_from_mssql
```

## Dashboard Usage

The `/admin/sync` page now includes a dedicated MSSQL Connection Status section that provides:

### Visual Status Indicators

- **✅ Green Badge**: Connected to MSSQL
- **❌ Red Badge**: Connection failed (with error message)
- **⚠️ Orange Badge**: MSSQL Not Configured

### Connection Details Card

A dedicated card showing:

- Connection status message
- Detailed error information if connection fails
- Server version when connected
- Configuration details

### Real-time Updates

The connection status is checked on each page refresh, providing up-to-date information about the MSSQL connection state.

## API Usage

### Kiroku.LegacyRepo.Inspector

You can also use the connection inspection utilities programmatically:

```elixir
# Get current configuration
config = Kiroku.LegacyRepo.Inspector.get_config()
# => %{hostname: "localhost", database: "legacy_db", port: 1433, ...}

# Test connection
case Kiroku.LegacyRepo.Inspector.test_connection() do
  {:ok, info} ->
    IO.puts("Connected to #{info.hostname}:#{info.port}")
    IO.puts("Server version: #{info.version}")

  {:error, reason} ->
    IO.puts("Connection failed: #{inspect(reason)}")
end

# Get human-readable status message
status = Kiroku.LegacyRepo.Inspector.status_message()
# => "Connected to MSSQL database 'legacy_db' on localhost:1433"
```

## Configuration

The connection inspection relies on the same environment variables as the regular MSSQL import:

- `MSSQL_HOST` - MSSQL server hostname
- `MSSQL_DB` - Database name
- `MSSQL_USER` - Username
- `MSSQL_PASS` - Password
- `MSSQL_PORT` - Port (optional, defaults to 1433)

## Error Handling

The connection inspection provides detailed error messages for common issues:

1. **Not Configured**: Missing required environment variables
2. **Repo Not Started**: LegacyRepo couldn't be initialized
3. **Connection Failed**: Network issues, incorrect credentials, or server not running
4. **Unexpected Response**: Server responded in an unexpected format

## Testing

The connection inspection includes comprehensive tests:

```bash
mix test test/kiroku/legacy_repo_inspector_test.exs
```

Tests cover:
- Configuration parsing and validation
- Version string extraction
- Connection status logic
- Error handling scenarios