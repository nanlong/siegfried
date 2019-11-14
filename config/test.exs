use Mix.Config

config :siegfried, env: :test

# Configure your database
config :siegfried, Siegfried.Repo,
  username: "postgres",
  password: "postgres",
  database: "siegfried_test",
  hostname: "localhost",
  pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :siegfried_web, SiegfriedWeb.Endpoint,
  http: [port: 4002],
  server: false

# Print only warnings and errors during test
config :logger, level: :warn

# Huobi config
config :trend_tracker, :huobi,
  spot_api: "https://api.huobi.vn",
  contract_api: "https://api.hbdm.vn",
  spot_ws: "wss://api.huobi.vn/ws",
  spot_auth_ws: "wss://api.huobi.vn/ws/v1",
  contract_ws: "wss://dm.huobi.vn/ws",
  contract_auth_ws: "wss://api.btcgateway.pro/notification",
  contract_symbols: []
