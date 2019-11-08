defmodule TrendTracker.Breakout.KeltnerChannel do
  @moduledoc """
  肯特钠通道
  """
  use TrendTracker.System

  def default do
    [period: 20, power: 2]
  end

  def indicators(state) do
    period = get_params(state, :period)
    power = get_params(state, :power)
    ema_key = "ema_#{period}"

    [
      :tr,
      {:atr, trunc(period / power)},
      [{:ema, "close", period}, rename: ema_key],
    ]
  end

  def klines(state) do
    period = get_params(state, :period)
    power = get_params(state, :power)
    ema_key = "ema_#{period}"
    atr_key = "atr_#{trunc(period / power)}"

    state[:klines]
    |> Enum.slice(-2, 2)
    |> Enum.map(fn kline ->
      upper = kline[ema_key] + kline[atr_key] * power
      lower = kline[ema_key] - kline[atr_key] * power

      kline = Map.take(kline, ["id", "datetime", "update_at", "open", "close", "high", "low"])
      Map.merge(kline, %{"upper" => upper, "mid" => kline[ema_key], "lower" => lower})
    end)
  end

  def signal(trade, state) do
    [pre_kline, cur_kline] = klines(state)
    trend = get_trend(state)
    position = get_position(state)

    cond do
      position.status == :filled && position.trend == :long && trade["price"] < cur_kline["mid"] ->
        {:close, position.trend, trade}

      position.status == :filled && position.trend == :short && trade["price"] > cur_kline["mid"] ->
        {:close, position.trend, trade}

      position.status == :empty && trend == :long && trade["price"] > pre_kline["upper"] ->
        {:open, trend, trade}

      position.status == :empty && trend == :short && trade["price"] < pre_kline["lower"] ->
        {:open, trend, trade}

      true ->
        {:wait, trend, trade}
    end
  end
end