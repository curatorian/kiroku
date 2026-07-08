# syntax=docker/dockerfile:1
#
# Kiroku — production OCI image (Podman / Docker / any OCI runtime)
#
#   Build:   podman build -t kiroku -f Containerfile .
#   Run:     podman run --rm -p 4000:4000 --env-file .env kiroku
#   Migrate: podman run --rm --env-file .env kiroku bin/migrate
#   Seed:    podman run --rm --env-file .env kiroku bin/seeds
#
# Two stages:
#   builder → compiles the Elixir release, builds & digests assets
#   runner  → slim image that runs the release as an unprivileged user
#
# Secrets (SECRET_KEY_BASE, DATABASE_URL, ...) are read at RUN time via
# config/runtime.exs, so they are never baked into the image.

# ─── Build arguments (bump versions here) ─────────────────────────────────────
# Match the toolchain you develop with. The app targets Elixir ~> 1.15.
# hexpm tags are dated; verify availability with:
#   curl -s "https://hub.docker.com/v2/repositories/hexpm/elixir/tags?name=1.18" | jq '.results[].name'
ARG ELIXIR_VERSION=1.18.4
ARG OTP_VERSION=27.3.4.14
ARG DEBIAN_VERSION=bookworm-20260623-slim

ARG BUILDER_IMAGE="docker.io/hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="docker.io/debian:${DEBIAN_VERSION}"

# ═════════════════════════════════════════════════════════════════════════════
#  Builder
# ═════════════════════════════════════════════════════════════════════════════
FROM ${BUILDER_IMAGE} AS builder

# build-essential + git → compile NIFs (bcrypt_elixir) and fetch the
# GitHub-hosted heroicons dependency; ca-certificates → verify TLS fetches.
RUN apt-get update -y && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    ca-certificates \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV MIX_ENV="prod"

RUN mix local.hex --force && mix local.rebar --force

# Fetch & compile dependencies first so the expensive deps layer is cached
# unless mix.exs / mix.lock change.
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV

# Compile-time config only (dev/test.exs are not needed for a prod build).
COPY config/config.exs config/prod.exs config/runtime.exs ./config/
RUN mix deps.compile

# Application source + static assets + seeds + migrations.
COPY lib lib
COPY priv priv
COPY assets assets
COPY rel rel

# Compile the application.
RUN mix compile

# Install the esbuild/tailwind binaries, then build & digest assets.
# assets.deploy = tailwind --minify + esbuild --minify + phx.digest, which
# generates priv/static/cache_manifest.json referenced by the endpoint.
RUN mix assets.setup && mix assets.deploy

# Assemble a self-contained, relocatable release.
RUN mix release

# ═════════════════════════════════════════════════════════════════════════════
#  Runner
# ═════════════════════════════════════════════════════════════════════════════
FROM ${RUNNER_IMAGE} AS runner

# Runtime libraries:
#   libstdc++6  → C++ ABI used by the BEAM JIT
#   libssl3     → :crypto / TLS for DB, S3, PAuS, Req
#   libncurses6 → enables `bin/kiroku remote` for live debugging
#   locales + ca-certificates → UTF-8 + verifying outbound TLS
RUN apt-get update -y && apt-get install -y --no-install-recommends \
    libstdc++6 \
    libssl3 \
    libncurses6 \
    locales \
    ca-certificates \
  && rm -rf /var/lib/apt/lists/*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG="en_US.UTF-8" \
    LANGUAGE="en_US:en" \
    LC_ALL="en_US.UTF-8"

# Run as an unprivileged user.
RUN useradd --create-home --uid 10001 app

WORKDIR /app
RUN chown app:app /app

# Copy the assembled release from the builder.
COPY --from=builder --chown=app:app /app/_build/prod/rel/kiroku ./

USER app

# Sensible production defaults. Override at runtime with `-e` / `--env-file`.
#   PHX_SERVER=true  → the endpoint starts automatically on boot.
#   ECTO_DB_SSL=true → encrypts the Postgres connection (DB is on another host).
ENV PHX_SERVER="true" \
    ECTO_DB_SSL="true" \
    PORT="4000" \
    HOME="/home/app"

EXPOSE 4000

# Boots the release detached; the endpoint starts because PHX_SERVER=true.
CMD ["bin/kiroku", "start"]
