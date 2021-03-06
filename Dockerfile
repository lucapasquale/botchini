# ---- Build Stage ----
FROM elixir:1.11-alpine as builder

ENV MIX_ENV=prod

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

CMD ["/app/bin/botchini", "start"]
