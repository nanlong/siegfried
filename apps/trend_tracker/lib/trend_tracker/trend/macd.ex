defmodule TrendTracker.Trend.Macd do
  @moduledoc """
  MACD - 异同移动平均线趋势过滤器

  {:ok, pid} = TrendTracker.Trend.Macd.start_link(exchange: "huobi", symbol: "BTC_CQ", period: "1week", source: Siegfried)
  """
  use TrendTracker.System

  def default do
    [fast: 12, slow: 26, signal: 9]
  end

  def indicators(state) do
    fast = get_params(state, :fast)
    slow = get_params(state, :slow)
    signal = get_params(state, :signal)
    ema_fast = "ema_#{fast}"
    ema_slow = "ema_#{slow}"

    [
      [{:ema, "close", fast}, rename: ema_fast],
      [{:ema, "close", slow}, rename: ema_slow],
      {:dif, ema_fast, ema_slow},
      [{:ema, "dif", signal}, rename: "dea"],
      {:hist, 1},
    ]
  end

  def klines(state) do
    state[:klines]
    |> Enum.slice(-2, 2)
    |> Enum.map(fn kline ->
      Map.take(kline, ["id", "datetime", "updated_at", "open", "close", "high", "low", "dif", "dea", "hist"])
    end)
  end

  def handle_call(:trend, _from, state) do
    [pre_kline, cur_kline] = Enum.slice(state[:klines], -2, 2)

    trend = cond do
      cur_kline["hist"] > pre_kline["hist"] && cur_kline["dif"] > cur_kline["dea"] -> :long
      cur_kline["hist"] < pre_kline["hist"] && cur_kline["dif"] < cur_kline["dea"] -> :short
      true -> nil
    end

    {:reply, {state[:symbol], trend}, state}
  end
end