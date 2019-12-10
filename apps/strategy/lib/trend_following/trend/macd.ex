defmodule Strategy.TrendFollowing.Trend.Macd do
  @moduledoc """
  MACD - 异同移动平均线趋势过滤器

  {:ok, pid} = Strategy.Trend.Macd.start_link(exchange: "huobi", symbol: "BTC_CQ", period: "1week", source: Siegfried)
  """
  use Strategy.TrendFollowing.System

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
    |> Enum.map(fn
      %{"dif" => _, "dea" => _, "hist" => _} = kline ->
        Map.merge(take_kline(kline), Map.take(kline, ["dif", "dea", "hist"]))

      kline ->
        take_kline(kline)
    end)
  end

  def handle_call(:trend, _from, state) do
    case klines(state) do
      [%{"hist" => _} = pre_kline, %{"dif" => _, "dea" => _, "hist" => _} = cur_kline] ->
        trend = cond do
          cur_kline["hist"] > pre_kline["hist"] && cur_kline["dif"] > cur_kline["dea"] -> :long
          cur_kline["hist"] < pre_kline["hist"] && cur_kline["dif"] < cur_kline["dea"] -> :short
          true -> nil
        end

        {:reply, {state[:symbol], trend}, state}

      _ ->
        {:reply, {state[:symbol], nil}, state}
    end
  end
end