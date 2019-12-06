#!/usr/bin/env bash
# Initial setup

# Get new version
# git pull

# Rm _build
rm -rf ./_build

DATABASE_URL="ecto://postgres:postgres@localhost/siegfried_prod"
SECRET_KEY_BASE="y50MEOMg0rA3xQqxo3A3f+/MmLOrPj2krBjK27WZfSX5HYQXSFCo/nplaPBl4lmr"
PORT=9001

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

# Stop application
./_build/prod/rel/siegfried/bin/siegfried stop

# Daemon application
./_build/prod/rel/siegfried/bin/siegfried daemon