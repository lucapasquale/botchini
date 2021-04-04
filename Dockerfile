# ---- Build Stage ----
FROM elixir:1.11-alpine as builder

ENV MIX_ENV=prod

# Env vars
ARG PORT=3010
ENV PORT=${PORT}

ARG HOST="default"
ENV HOST=${HOST}

ARG DISCORD_TOKEN="default"
ENV DISCORD_TOKEN=${DISCORD_TOKEN}

ARG POSTGRES_URL="default"
ENV POSTGRES_URL=${POSTGRES_URL}

ARG TWITCH_CLIENT_ID="default"
ENV TWITCH_CLIENT_ID=${TWITCH_CLIENT_ID}

ARG TWITCH_CLIENT_SECRET="default"
ENV TWITCH_CLIENT_SECRET=${TWITCH_CLIENT_SECRET}

COPY lib ./lib
COPY config ./config
COPY mix.exs .
COPY mix.lock .

RUN mix local.rebar --force \
  && mix local.hex --force \
  && mix deps.get \
  && mix release

# ---- Application Stage ----
FROM alpine:3

RUN apk add --no-cache --update bash openssl

WORKDIR /app

COPY --from=builder _build/prod/rel/botchini/ .

# Migrate DB
RUN /app/bin/botchini eval "Botchini.Release.migrate"

CMD ["/app/bin/botchini", "start"]
