# STEP 1 - BUILD RELEASE
FROM hexpm/elixir:1.12.3-erlang-24.0.1-alpine-3.13.3 AS build

# Install build dependencies
RUN apk update && \
  apk upgrade --no-cache && \
  apk add --no-cache \
  git \
  build-base \
  nodejs-current \
  nodejs-npm \
  python3 && \
  mix local.rebar --force && \
  mix local.hex --force

ENV MIX_ENV=prod
WORKDIR /app

# Install elixir package dependencies
COPY mix.exs /app/mix.exs
COPY mix.lock /app/mix.lock
RUN mix do deps.get --only $MIX_ENV, deps.compile

# copy config, priv and release and application directories
COPY config /app/config
COPY priv /app/priv
COPY lib /app/lib

# compile app and create release
RUN mix do compile, release

####################################################################################################
# STEP 2 - FINAL
FROM alpine:3.13.2 as app
RUN apk update && \
  apk upgrade --no-cache && \
  apk add --no-cache \
  openssl \
  ncurses-libs \
  python3 \
  py3-pip \
  ffmpeg

RUN wget https://yt-dl.org/downloads/latest/youtube-dl -O /usr/local/bin/youtube-dl && \
  chmod a+rx /usr/local/bin/youtube-dl

WORKDIR /app

RUN chown nobody:nobody /app

USER nobody:nobody

COPY --from=build --chown=nobody:nobody /app/_build/prod/rel/botchini ./

ENV HOME=/app

CMD bin/botchini eval "Botchini.Release.migrate" && bin/botchini start
