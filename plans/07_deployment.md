# Deployment Guide

## Kiroku — Podman Deployment with Remote PostgreSQL

---

## 0. Architecture

```
┌─────────────────────┐         ┌─────────────────────┐
│   App Machine       │         │   DB Machine         │
│                     │         │                      │
│  Podman             │  TCP    │  PostgreSQL 14+      │
│  └─ kiroku_app      │◄───────►│  (port 5432, TLS)    │
│     (port 4000)     │         │                      │
│                     │         │  Database: kiroku    │
│  priv/uploads vol   │         │  User: kiroku_user   │
└─────────────────────┘         └─────────────────────┘
```

- The app runs as a Podman container on the app machine
- The database is on a separate machine and is reached over the network
- All secrets are read at runtime from environment variables (`.env` file)
- The container image is self-contained — no Elixir/Mix needed on the host

---

## 1. Prerequisites

### App machine

- **Podman** 4.x+ (`podman --version`)
- **podman-compose** (`podman compose version`) — included with Podman 4.7+
- Network access to the DB machine on port 5432
- Outbound internet access (for pulling base images on first build)

### DB machine

- **PostgreSQL** 14+
- Database, user, and password already created (you said this is done)
- Network access from the app machine's IP on port 5432

---

## 2. Database Machine Preparation

### 2.1 Enable remote connections

In `postgresql.conf` (typically `/etc/postgresql/<version>/main/postgresql.conf`):

```conf
listen_addresses = '*'
# Or restrict to the app machine's IP:
# listen_addresses = '10.0.0.5'
```

### 2.2 Allow the app machine to connect

In `pg_hba.conf` (typically `/etc/postgresql/<version>/main/pg_hba.conf`):

```conf
# Allow the app machine's IP with TLS
# TYPE  DATABASE  USER         ADDRESS          METHOD
hostssl kiroku    kiroku_user  10.0.0.5/32      scram-sha-256

# If TLS is not configured, use hostnossl or md5:
# host    kiroku    kiroku_user  10.0.0.5/32      md5
```

Restart PostgreSQL after changes:

```bash
sudo systemctl restart postgresql
```

### 2.3 TLS (recommended)

The app defaults to `ECTO_DB_SSL=true`, which encrypts all DB traffic. PostgreSQL needs TLS enabled:

```bash
# Check if TLS is enabled
sudo -u postgres psql -c "SHOW ssl;"
#  ssl
# ------
# on     ← good
```

If TLS is off, enable it in `postgresql.conf`:

```conf
ssl = on
ssl_cert_file = '/etc/ssl/certs/ssl-cert-snakeoil.pem'
ssl_key_file = '/etc/ssl/private/ssl-cert-snakeoil.key'
```

For production, use real certificates (Let's Encrypt or your institution's CA).

**If your PostgreSQL does not support TLS**, set `ECTO_DB_SSL=false` in your `.env` file.

### 2.4 Verify connectivity from the app machine

```bash
# From the app machine, test the connection:
psql "host=DB_MACHINE_IP port=5432 dbname=kiroku user=kiroku_user sslmode=require"
```

---

## 3. App Machine Preparation

### 3.1 Clone the repository

```bash
git clone <repo-url> /opt/kiroku
cd /opt/kiroku
```

### 3.2 Create the `.env` file

```bash
cp .env.example .env
```

Fill in the **required** values:

```bash
# ── REQUIRED ──────────────────────────────────────────────

# Generate a secret key (run this on any machine with Elixir installed,
# or use: openssl rand -base64 48)
mix phx.gen.secret
# Paste the output here:
SECRET_KEY_BASE=<your-generated-secret>

# Point to the remote database
DATABASE_URL=ecto://kiroku_user:YOUR_PASSWORD@DB_MACHINE_IP/kiroku

# Your domain or the app machine's public IP
PHX_HOST=kiroku.yourdomain.ac.id

# URL scheme/port for external URL generation (emails, OAI-PMH, redirects).
# Defaults to https / 443. Override only when accessing via IP without SSL:
#   PHX_SCHEME=http
#   PHX_URL_PORT=4000

# ── Defaults (usually fine as-is) ────────────────────────

PHX_SERVER=true          # starts the HTTP server on boot
PORT=4000                # port the container listens on
ECTO_DB_SSL=true         # encrypts DB traffic (set to false if DB has no TLS)
POOL_SIZE=10             # DB connection pool size
STORAGE_ADAPTER=local    # files stored in a volume on the app machine
```

### 3.3 Optional values

Uncomment and fill in only what you need:

```bash
# ── PAuS SSO (if using Padjadjaran Authentication Service) ──
KIROKU_PAUS_CLIENT_ID=your_client_id
KIROKU_PAUS_CLIENT_SECRET=your_client_secret
KIROKU_PAUS_REDIRECT_URI=https://kiroku.yourdomain.ac.id/auth/paus/callback

# ── MSSQL Legacy Import (if syncing from old system) ──
# MSSQL_HOST=mssql.yourdomain.ac.id
# MSSQL_PORT=1433
# MSSQL_DB=LegacyThesis
# MSSQL_USER=sa
# MSSQL_PASS=your_password

# ── Email (if sending notifications) ──
# MAILER_PROVIDER=smtp
# MAILER_FROM=noreply@kiroku.yourdomain.ac.id
# SMTP_HOST=smtp.yourprovider.com
# SMTP_PORT=587
# SMTP_USERNAME=your_username
# SMTP_PASSWORD=your_password

# ── S3 Storage (if using S3 instead of local) ──
# STORAGE_ADAPTER=s3
# S3_BUCKET=kiroku-uploads
# S3_REGION=ap-southeast-1
# S3_ACCESS_KEY_ID=your_key
# S3_SECRET_ACCESS_KEY=your_secret
# S3_ENDPOINT=                  # for MinIO/R2, leave blank for AWS
```

---

## 4. Build & Deploy

### 4.1 Build the image and start the container

```bash
podman compose up -d --build
```

This builds the OCI image (multi-stage: Elixir compile → slim Debian runner) and starts the container in detached mode. First build takes ~5-10 minutes; subsequent builds use cached layers.

### 4.2 Run database migrations (first time only)

> **The database must already exist.** `bin/migrate` runs Ecto migrations but
> does not create the database itself. Create it on the DB machine beforehand:
>
> ```bash
> sudo -u postgres createdb kiroku
> sudo -u postgres psql -c "GRANT ALL ON DATABASE kiroku TO kiroku_user;"
> ```

```bash
podman compose run --rm app bin/migrate
```

This runs all Ecto migrations, including the Oban jobs table.

### 4.3 Run seeds (first time only)

```bash
podman compose run --rm app bin/seeds
```

Seeds populate default system settings (brand name, handle prefix, etc.) and are idempotent — safe to run multiple times.

### 4.4 Verify the app is running

```bash
# Check container status
podman compose ps

# Check health
curl http://localhost:4000/health
# Expected: {"status":"ok"}

# View logs
podman compose logs -f app
```

### 4.5 Complete the first-run setup wizard

Open `http://APP_MACHINE_IP:4000` in your browser. On first boot, the app redirects to `/setup` — an onboarding wizard that lets you:

1. Set the brand name, tagline, and description
2. Configure storage (local or S3)
3. Create the first admin user
4. Optionally configure the mailer

Once the wizard is complete, all routes become accessible.

#### Accessing via IP before the domain is configured

If you don't have a domain or reverse proxy yet, set these in `.env` so Phoenix generates correct URLs (otherwise redirects will point to `https://your-domain:443` and fail):

```bash
PHX_HOST=xxx.xxx.xxx.xxx       # the app machine's IP
PHX_SCHEME=http
PHX_URL_PORT=4000
```

Rebuild after changing `.env`:

```bash
podman compose down
podman compose up -d --build
```

When IT points the domain and you set up a reverse proxy with TLS, switch back to defaults:

```bash
PHX_HOST=kiroku.yourdomain.ac.id
# Remove or comment out PHX_SCHEME and PHX_URL_PORT — they default to https / 443
```

Then rebuild again.

---

## 5. Reverse Proxy (recommended for production)

For TLS termination and proper domain handling, put a reverse proxy in front of the app. The app does **not** use `force_ssl` — the reverse proxy is responsible for HTTP→HTTPS redirect and HSTS headers.

### 5.1 Caddy (simplest — automatic HTTPS)

```
kiroku.yourdomain.ac.id {
    reverse_proxy localhost:4000
}
```

### 5.2 Nginx

```nginx
server {
    listen 443 ssl http2;
    server_name kiroku.yourdomain.ac.id;

    ssl_certificate     /etc/ssl/certs/kiroku.pem;
    ssl_certificate_key /etc/ssl/private/kiroku.key;

    location / {
        proxy_pass http://localhost:4000;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # LiveView WebSocket support
    location /live {
        proxy_pass http://localhost:4000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

When behind a reverse proxy, set `PHX_HOST` to your public domain:

```bash
PHX_HOST=kiroku.yourdomain.ac.id
```

---

## 6. MSSQL Legacy Import (optional)

If migrating data from the old MSSQL system, set the `MSSQL_*` env vars in `.env` and restart:

```bash
podman compose down
podman compose up -d --build
```

Then run the import using the `bin/import_from_mssql` overlay script (ships inside the release — no Mix needed):

```bash
# Test the connection first
podman compose run --rm app bin/import_from_mssql --check-connection

# Dry run (5 records per view, no writes)
podman compose run --rm app bin/import_from_mssql --dry-run

# Dry run with a custom sample size
podman compose run --rm app bin/import_from_mssql --dry-run --limit 20

# Full import (all four views)
podman compose run --rm app bin/import_from_mssql

# Single view only
podman compose run --rm app bin/import_from_mssql --view Skripsi

# Incremental sync (only changed records since last run)
podman compose run --rm app bin/import_from_mssql --incremental

# Custom batch size
podman compose run --rm app bin/import_from_mssql --batch-size 500
```

Alternatively, use the `bin/sync_mssql` script from the host (it has a container mode):

```bash
KIROKU_CONTAINER=kiroku_app bin/sync_mssql --dry-run
```

> **Note:** `Mix.Task.run/2` is not available inside production releases. Always
> use `bin/import_from_mssql` (or `bin/kiroku eval "Kiroku.Release.import_from_mssql([...]"`)
> — never `bin/kiroku eval 'Mix.Task.run(...)'`.

---

## 7. Routine Operations

### View logs

```bash
podman compose logs -f app          # follow
podman compose logs --tail 100 app  # last 100 lines
```

### Restart the app

```bash
podman compose restart app
```

### Update to a new version

```bash
bin/deploy                 # pull, rebuild, restart
```

After updating dependencies (`mix.exs`/`mix.lock` changes), add `--no-cache`:

```bash
bin/deploy --no-cache      # full rebuild, no layer cache
```

If there are new database migrations:

```bash
bin/deploy --migrate       # rebuild + restart + run migrations
```

Other commands:

```bash
bin/deploy --status        # show container status + recent logs
bin/deploy --logs          # follow app logs (Ctrl-C to stop)
bin/deploy --shell         # open a remote IEx shell inside the container
```

### Change `.env` and apply changes

Environment variables are read at container start time. After editing `.env`, you must recreate the container for changes to take effect:

```bash
podman compose down
podman compose up -d --build
```

> **You do not need to rebuild the image just for `.env` changes.** The `.env`
> file is read at runtime, not baked into the image. However, `podman compose up`
> alone may not pick up env changes if the container already exists — use
> `down` + `up` (or `--force-recreate`) to be safe. Use `--build` only when code
> or config files inside the image changed (e.g., after `git pull`).

### Stop / start

```bash
podman compose down      # stop and remove containers (volume preserved)
podman compose up -d     # start again
```

### Access the running app's IEx shell

```bash
podman exec -it kiroku_app bin/kiroku remote
```

### Check container health

```bash
podman inspect --format='{{.State.Health.Status}}' kiroku_app
```

---

## 8. Backup Strategy

### Database

Set up a daily `pg_dump` cron job on the DB machine:

```bash
pg_dump -U kiroku_user -h localhost kiroku | gzip > /backups/kiroku_$(date +%Y%m%d).sql.gz
# Retain 30 days
find /backups -name "kiroku_*.sql.gz" -mtime +30 -delete
```

### Local uploads (if `STORAGE_ADAPTER=local`)

The uploads are in a named Podman volume. Back it up:

```bash
podman volume inspect kiroku_uploads  # find the mount path
# Or tar directly:
podman run --rm -v kiroku_uploads:/data -v /backups:/backup alpine \
  tar czf /backup/kiroku_uploads_$(date +%Y%m%d).tar.gz -C /data .
```

---

## 9. Troubleshooting

### App won't start — `DATABASE_URL is missing`

The `.env` file is not being loaded. Verify it exists and `podman compose` is using it:

```bash
podman compose config | grep DATABASE_URL
```

### App won't start — SSL connection failed to PostgreSQL

The DB doesn't have TLS enabled. Either enable TLS on PostgreSQL (see §2.3) or set `ECTO_DB_SSL=false` in `.env`.

### App won't start — `SECRET_KEY_BASE is missing`

Generate one and add it to `.env`:

```bash
openssl rand -base64 48
```

### Health check shows `unhealthy`

```bash
podman compose logs --tail 50 app
```

Common causes: DB unreachable, migrations not run, or the app crashed during boot.

### Can't connect to the DB from the container

Check that the DB machine's firewall allows connections from the app machine:

```bash
# On the DB machine
sudo ufw allow from APP_MACHINE_IP to any port 5432
```

Also verify `pg_hba.conf` has an entry for the app machine's IP (see §2.2).

### Redirects to wrong host / HTTPS when accessing via IP

If you set `PHX_HOST` to your eventual domain but are still accessing via `http://10.x.xxx.xx:4000`, Phoenix generates redirect URLs pointing to `https://your-domain:443/...`, which fail. Fix this by setting the URL scheme and port to match your actual access URL:

```bash
# In .env — temporary until the domain + reverse proxy are ready
PHX_HOST=10.x.xxx.xx
PHX_SCHEME=http
PHX_URL_PORT=4000
```

Then rebuild:

```bash
podman compose down && podman compose up -d --build
```

When the domain and reverse proxy are ready, switch `PHX_HOST` back to the domain and remove `PHX_SCHEME` / `PHX_URL_PORT` (they default to `https` / `443`).

> **Note:** The app does NOT use `force_ssl` — HTTP→HTTPS redirect and HSTS are
> handled by the reverse proxy (Caddy/Nginx). This allows direct HTTP access
> during initial setup before the domain and TLS are configured.

---

## 10. Environment Variable Reference

| Variable | Required | Default | Description |
|---|---|---|---|
| `SECRET_KEY_BASE` | **Yes** | — | Signs/encrypts cookies and secrets |
| `DATABASE_URL` | **Yes** | — | Ecto connection URL (`ecto://user:pass@host/db`) |
| `PHX_HOST` | **Yes** | `example.com` | Public hostname for URL generation |
| `PHX_SCHEME` | No | `https` | URL scheme for external links (`http` or `https`) |
| `PHX_URL_PORT` | No | `443` | URL port for external links (not the listen port) |
| `PHX_SERVER` | No | `true` | Starts the HTTP endpoint on boot |
| `PORT` | No | `4000` | HTTP listen port |
| `ECTO_DB_SSL` | No | `true` | Encrypts PostgreSQL connection |
| `POOL_SIZE` | No | `10` | DB connection pool size |
| `ECTO_IPV6` | No | `false` | Use IPv6 for DB connection |
| `STORAGE_ADAPTER` | No | `local` | `local` or `s3` |
| `S3_BUCKET` | No | `kiroku-uploads` | S3 bucket name |
| `S3_REGION` | No | `ap-southeast-1` | S3 region |
| `S3_ACCESS_KEY_ID` | No | — | S3 access key |
| `S3_SECRET_ACCESS_KEY` | No | — | S3 secret key |
| `S3_ENDPOINT` | No | — | Custom S3-compatible API URL |
| `S3_PUBLIC_URL` | No | — | Override for public file URLs |
| `MSSQL_HOST` | No | — | Enables legacy import if set |
| `MSSQL_PORT` | No | `1433` | MSSQL server port |
| `MSSQL_DB` | No | — | MSSQL database name |
| `MSSQL_USER` | No | — | MSSQL username |
| `MSSQL_PASS` | No | — | MSSQL password |
| `KIROKU_PAUS_CLIENT_ID` | No | — | PAuS OAuth client ID |
| `KIROKU_PAUS_CLIENT_SECRET` | No | — | PAuS OAuth client secret |
| `KIROKU_PAUS_REDIRECT_URI` | No | — | PAuS OAuth callback URL |
| `MAILER_PROVIDER` | No | `local` | `local` or `smtp` |
| `MAILER_FROM` | No | `noreply@kiroku.local` | Sender email address |
| `SMTP_HOST` | No | — | SMTP server hostname |
| `SMTP_PORT` | No | `587` | SMTP server port |
| `SMTP_USERNAME` | No | — | SMTP username |
| `SMTP_PASSWORD` | No | — | SMTP password |
| `DNS_CLUSTER_QUERY` | No | — | DNS-based node discovery (multi-node) |
| `EMBARGO_CRON` | No | `0 2 * * *` | Embargo lifter cron schedule |
