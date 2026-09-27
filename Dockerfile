# Find eligible builder and runner images on Docker Hub. We use Ubuntu/Debian
# instead of Alpine to avoid DNS resolution issues in production.
#
# https://hub.docker.com/r/hexpm/elixir/tags?page=1&name=ubuntu
# https://hub.docker.com/_/ubuntu?tab=tags
#
# This file is based on these images:
#
#   - https://hub.docker.com/r/hexpm/elixir/tags - for the build image
#   - https://hub.docker.com/_/debian?tab=tags&page=1&name=bullseye-20240513-slim - for the release image
#   - https://pkgs.org/ - resource for finding needed packages
#   - Ex: hexpm/elixir:1.16.2-erlang-26.2.5-debian-bullseye-20240513-slim
#
ARG ELIXIR_VERSION=1.20.4
ARG OTP_VERSION=29.1.1
ARG DEBIAN_VERSION=bookworm-20260918-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

# install build dependencies
RUN apt-get update -y && apt-get install -y build-essential git \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

# prepare build dir
WORKDIR /app

# install hex + rebar
RUN mix local.hex --force && \
  mix local.rebar --force

# set build ENV
ENV MIX_ENV="prod"

# install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY priv priv

COPY lib lib

COPY assets assets

# compile assets
RUN mix assets.deploy

# Compile the release
RUN mix compile

# Changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/

COPY rel rel
RUN mix release

# start a new build stage so that the final image will only contain
# the compiled release and other runtime necessities
FROM ${RUNNER_IMAGE}

RUN apt-get update -y \
  && apt-get install -y software-properties-common libstdc++6 openssl libncurses5 locales ffmpeg curl fuse libfuse2 python3 python3-pip \
  && apt-get clean \
  && rm -f /var/lib/apt/lists/*_*

# Install deno, the JS runtime yt-dlp needs to solve YouTube's JS challenges
COPY --from=denoland/deno:bin-2.9.7 /deno /usr/local/bin/deno

# Install yt-dlp
RUN curl -L https://github.com/yt-dlp/yt-dlp/releases/download/2026.08.19/yt-dlp -o /usr/local/bin/yt-dlp \
  && chmod a+rx /usr/local/bin/yt-dlp

# Install streamlink
RUN curl -L https://github.com/streamlink/streamlink-appimage/releases/download/8.6.1-1/streamlink-8.6.1-1-cp314-cp314-manylinux_2_28_x86_64.AppImage -o /usr/local/bin/streamlink \
  && chmod a+rx /usr/local/bin/streamlink

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR "/app"
RUN chown nobody /app

# set runner ENV
ENV MIX_ENV="prod"

# Only copy the final release from the build stage
COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/botchini ./

USER nobody

CMD ["/app/bin/server"]
