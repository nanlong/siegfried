defmodule TrendTracker.Trend.Ema do
  @moduledoc """
  指数移动平均趋势过滤器
  """

  use TrendTracker.System

  def default do
    [fast: 20, slow: 120]
  end

  def indicators(state) do
    fast = get_params(state, :fast)
    slow = get_params(state, :slow)

    [
      [{:ema, "close", fast}, rename: "ema_fast"],
      [{:ema, "close", slow}, rename: "ema_slow"],
    ]
  end

  def handle_call(:trend, _from, state) do
    [_pre_kline, cur_kline] = Enum.slice(state[:klines], -2, 2)

    trend = cond do
      cur_kline["ema_fast"] > cur_kline["ema_slow"] -> :long
      cur_kline["ema_fast"] < cur_kline["ema_slow"] -> :short
      true -> nil
    end

    {:reply, {state[:symbol], trend}, state}
  end
end