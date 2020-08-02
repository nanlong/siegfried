defmodule Strategy.TrendFollowing.Master do
  @moduledoc """

  opts = [
    title: "myokex",
    balance: 2515,
    exchange: "okex",
    market: "swap",
    symbols: ~w(BTC-USD-SWAP ETH-USD-SWAP EOS-USD-SWAP BCH-USD-SWAP),
    auth: {"siegfried", "f4f08729-845e-4352-b196-4b98e6ef57b2", "2AFA216F0065567490B13F4ECD30DA02"},
    source: Siegfried,
    trend: [module: "Macd", period: "1week"],
    breakout: [module: "BollingerBands", period: "1day"],
    bankroll: [period: "1day"],
    trader: [],
    dingding: "https://oapi.dingtalk.com/robot/send?access_token=b9a187ce8a56665c0c6215233cc97bdd1b5c0ad8dd8c9e342a9c4416a9b219c9",
  ]

  Strategy.TrendFollowing.Master.start(opts)
  """

  use DynamicSupervisor

  alias Strategy.TrendFollowing.Worker

  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, opts ++ [name: __MODULE__])
  end

  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start(opts) when is_list(opts) do
    worker_name = String.to_atom(opts[:title])
    {:ok, worker_pid} = DynamicSupervisor.start_child(__MODULE__, {Worker, [name: worker_name]})
    ConCache.put(:strategy, worker_name, worker_pid)
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
    worker_pid = ConCache.get(:strategy, worker_name)

    children = DynamicSupervisor.which_children(__MODULE__)
    worker = Enum.find(children, fn {_, pid, _, _} -> pid == worker_pid end)

    if worker, do: worker_pid
  end
end
