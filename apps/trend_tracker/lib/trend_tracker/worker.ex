defmodule TrendTracker.Worker do
  @moduledoc """
  opts = [
    title: "test",
    balance: 10000,
    exchange: "huobi",
    symbols: ["BTC_CQ"],
    source: Siegfried,
    trend: [module: "Macd", period: "1week"],
    breakout: [module: "BollingerBands", period: "1day"],
    turtle: [period: "1day"],
    trader: [],
  ]

  {:ok, pid} = TrendTracker.Worker.start_link()
  TrendTracker.Worker.start(pid, opts)
  """

  use DynamicSupervisor

  alias TrendTracker.Helper
  alias TrendTracker.Exchange.Huobi.Account, as: HuobiAccount
  alias TrendTracker.Trend.{Macd, Ema}
  alias TrendTracker.Breakout.{BollingerBands, KeltnerChannel, DonchainChanel}
  alias TrendTracker.Bankroll.Turtle
  alias TrendTracker.Trader

  require Logger

  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, :ok, opts)
  end

  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  开始
  """
  def start(pid, opts) do
    account_name = Helper.system_name("account", Keyword.take(opts, [:title, :exchange, :backtest]))
    {:ok, _account_pid} = start_child(pid, {HuobiAccount, [name: account_name] ++ Keyword.take(opts, [:balance, :symbols])})

    Enum.each(opts[:symbols], fn symbol ->
      public_opts = Keyword.take(opts, [:title, :exchange, :source, :backtest]) ++ [symbol: symbol]

      trend_name = Helper.system_name("trend", public_opts)
      breakout_name = Helper.system_name("breakout", public_opts)
      bankroll_name = Helper.system_name("bankroll", public_opts)
      trader_name = Helper.system_name("trader", public_opts)

      trend_module = trend_module(opts[:trend][:module])
      breakout_module = breakout_module(opts[:breakout][:module])

      systems = [account: account_name, trend: trend_name, breakout: breakout_name, bankroll: bankroll_name, trader: trader_name]

      trend_opts = [name: trend_name, systems: systems] ++ opts[:trend] ++ public_opts
      {:ok, _trend_pid} = start_child(pid, {trend_module, trend_opts})
      breakout_opts = [name: breakout_name, systems: systems] ++ opts[:breakout] ++ public_opts
      {:ok, _breakout_pid} = start_child(pid, {breakout_module, breakout_opts})
      bankroll_opts = [name: bankroll_name, systems: systems] ++ opts[:turtle] ++ public_opts
      {:ok, _bankroll_pid} = start_child(pid, {Turtle, bankroll_opts})
      trader_opts = [name: trader_name, systems: systems] ++ opts[:trader] ++ public_opts
      {:ok, _trader_pid} = start_child(pid, {Trader, trader_opts})
    end)
  end

  @doc """
  停止
  """
  def stop(pid) do
    pid
    |> DynamicSupervisor.which_children()
    |> Enum.each(fn {_, child_pid, _, [child_module]} ->
      DynamicSupervisor.terminate_child(pid, child_pid)
      Logger.debug "terminate #{child_module}"
    end)
  end

  @doc """
  趋势
  """
  def trend(pid), do: system_data(pid, trend_modules(), :trend)

  @doc """
  持仓
  """
  def position(pid), do: system_data(pid, Turtle, :position)

  @doc """
  k线
  """
  def kline(pid), do: Map.new([:trend, :breakout, :bankroll], &({&1, kline(pid, &1)}))
  def kline(pid, :trend), do: system_data(pid, trend_modules(), :klines)
  def kline(pid, :breakout), do: system_data(pid, breakout_modules(), :klines)
  def kline(pid, :bankroll), do: system_data(pid, Turtle, :klines)

  defp trend_modules, do: [Macd, Ema]

  defp trend_module("Macd"), do: Macd
  defp trend_module("Ema"), do: Ema

  defp breakout_modules, do: [BollingerBands, KeltnerChannel, DonchainChanel]

  defp breakout_module("BollingerBands"), do: BollingerBands
  defp breakout_module("KeltnerChannel"), do: KeltnerChannel
  defp breakout_module("DonchainChanel"), do: DonchainChanel

  # 系统通信，获取相关模块的指定数据
  defp system_data(pid, modules, field) do
    pids = children(pid, modules)
    Map.new(pids, fn child_pid -> GenServer.call(child_pid, field) end)
  end

  defp start_child(pid, child_spec) do
    DynamicSupervisor.start_child(pid, child_spec)
  end

  defp children(pid, module) when is_atom(module), do: children(pid, [module])
  defp children(pid, modules) when is_list(modules) do
    pid
    |> DynamicSupervisor.which_children()
    |> Enum.filter(fn {_, _, _, [child_module]} -> child_module in modules end)
    |> Enum.map(fn {_, child_pid, _, _} -> child_pid end)
  end
end