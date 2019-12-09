#!/usr/bin/env bash
# Initial setup

# Get new version
# git pull

# Rm _build
rm -rf ./_build

# Get and compile
mix deps.get --only prod
MIX_ENV=prod mix compile

# Compile assets
npm install --prefix ./apps/siegfried_web/assets
npm run deploy --prefix ./apps/siegfried_web/assets
cd ./apps/siegfried_web && MIX_ENV=prod mix phx.digest

# Build the release
cd ../..
MIX_ENV=prod mix release

# Migrate database
MIX_ENV=prod mix ecto.create
MIX_ENV=prod mix ecto.migrate

# Daemon application
./_build/prod/rel/siegfried/bin/siegfried daemon