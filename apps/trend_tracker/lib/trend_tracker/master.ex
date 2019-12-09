defmodule TrendTracker.Master do
  @moduledoc """

  opts = [
    title: "test",
    balance: 10000,
    exchange: "okex",
    market: "swap",
    symbols: ~w(BTC-USD-SWAP ETH-USD-SWAP EOS-USD-SWAP BCH-USD-SWAP),
    auth: {"passphrase", "access_key", "secret_key"},
    source: Siegfried,
    trend: [module: "Macd", period: "1week"],
    breakout: [module: "BollingerBands", period: "1day"],
    bankroll: [period: "1day"],
    trader: [],
  ]

  TrendTracker.Master.start(opts)
  """

  use DynamicSupervisor

  alias TrendTracker.Worker

  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, opts ++ [name: __MODULE__])
  end

  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start(opts) when is_list(opts) do
    worker_name = String.to_atom(opts[:title])
    {:ok, worker_pid} = DynamicSupervisor.start_child(__MODULE__, {Worker, [name: worker_name]})
    ConCache.put(:trend_tracker, worker_name, worker_pid)
    Worker.start(worker_pid, opts)
  end

  def start(name, source) do
    {_, opts} = apply(source, :get_cache, [name])
    start(opts)
  end

  def stop(name) do
    worker_pid = get_worker(name)

    if worker_pid do
      Worker.stop(worker_pid)
      DynamicSupervisor.terminate_child(__MODULE__, worker_pid)
    end
  end

  def trend(name) do
    worker_pid = get_worker(name)

    if worker_pid do
      Worker.trend(worker_pid)
    end
  end

  def position(name) do
    worker_pid = get_worker(name)

    if worker_pid do
      Worker.position(worker_pid)
    end
  end

  def kline(name, system \\ nil) do
    worker_pid = get_worker(name)

    if worker_pid do
      Worker.kline(worker_pid, system)
    end
  end

  def woker_which_children(name) do
    worker_pid = get_worker(name)

    if worker_pid do
      DynamicSupervisor.which_children(worker_pid)
    end
  end

  defp get_worker(name) do
    worker_name = String.to_atom(name)
    worker_pid = ConCache.get(:trend_tracker, worker_name)

    children = DynamicSupervisor.which_children(__MODULE__)
    worker = Enum.find(children, fn {_, pid, _, _} -> pid == worker_pid end)

    if worker, do: worker_pid
  end
end