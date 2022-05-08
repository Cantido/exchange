# SPDX-FileCopyrightText: 2021 Rosa Richter
#
# SPDX-License-Identifier: MIT

VERSION 0.6

ARG MIX_ENV=dev

all:
  BUILD +test

get-deps:
  FROM elixir:1.13-alpine
  RUN mix do local.rebar --force, local.hex --force
  COPY mix.exs .
  COPY mix.lock .

  RUN mix deps.get

compile-deps:
  FROM +get-deps
  RUN MIX_ENV=$MIX_ENV mix deps.compile

build:
  FROM +compile-deps

  COPY config ./config
  COPY priv ./priv
  COPY lib ./lib

  RUN MIX_ENV=$MIX_ENV mix compile

test:
  FROM --build-arg MIX_ENV=test +build

  COPY test ./test
  COPY docker-compose.yml .

  WITH DOCKER --compose docker-compose.yml
    RUN MIX_ENV=test mix test
  END
