# This file is responsible for configuring your umbrella
# and **all applications** and their dependencies with the
# help of Mix.Config.
#
# Note that all applications in your umbrella share the
# same configuration and dependencies, which is why they
# all use the same configuration file. If you want different
# configurations or dependencies per app, it is best to
# move said applications out of the umbrella.
use Mix.Config

# Configure Mix tasks and generators
config :siegfried,
  ecto_repos: [Siegfried.Repo]

config :siegfried_web,
  ecto_repos: [Siegfried.Repo],
  generators: [context_app: :siegfried]

# Configures the endpoint
config :siegfried_web, SiegfriedWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "fNC8ZzUXNPtftt7CejxMktLT5rORmvi+4eGfFgGTxWiVo9DactCasYTJrshOFmos",
  render_errors: [view: SiegfriedWeb.ErrorView, accepts: ~w(html json)],
  pubsub: [name: SiegfriedWeb.PubSub, adapter: Phoenix.PubSub.PG2],
  instrumenters: [Appsignal.Phoenix.Instrumenter]

config :phoenix, :template_engines,
  eex: Appsignal.Phoenix.Template.EExEngine,
  exs: Appsignal.Phoenix.Template.ExsEngine

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

import_config "appsignal.exs"

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
