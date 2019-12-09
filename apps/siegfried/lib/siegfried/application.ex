defmodule Siegfried.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      Siegfried.Repo,
      Siegfried.HuobiSupervisor,
      Siegfried.OkexSupervisor,
      {ConCache, [name: :okex, ttl_check_interval: false]}
    ]

    :telemetry.attach(
      "appsignal-ecto",
      [:hermes, :repo, :query],
      &Appsignal.Ecto.handle_event/4,
      nil
    )

    Supervisor.start_link(children, strategy: :one_for_one, name: Siegfried.Supervisor)
  end
end
