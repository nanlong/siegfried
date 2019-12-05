defmodule TrendTracker.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      # Starts a worker by calling: TrendTracker.Worker.start_link(arg)
      # {TrendTracker.Worker, arg}
      {ConCache, [name: :trend_tracker, ttl_check_interval: false]},
      {TrendTracker.Master, []},
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: TrendTracker.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
