defmodule TrendTracker.Breakout.BollingerBands do
  @moduledoc """
  布林带

  opts = [
    systems: [
      trend: nil,
      bankroll: nil,
    ],
    indicators: [
      period: 20,
      power: 2,
    ]
  ]

  BollingerBands.start_link(klines, period, opts)
  """

  use TrendTracker.System

  def default do
    [period: 20, power: 2]
  end

  def indicators(state) do
    period = get_params(state, :period)
    ma_key = "ma_#{period}"
    md_key = "md_#{period}"

    [
      [{:ma, "close", period}, rename: ma_key],
      [{:md, ma_key, period}, rename: md_key],
    ]
  end

  def klines(state) do
    period = get_params(state, :period)
    power = get_params(state, :power)
    ma_key = "ma_#{period}"
    md_key = "md_#{period}"

    state[:klines]
    |> Enum.slice(-2, 2)
    |> Enum.map(fn kline ->
      upper = kline[ma_key] + kline[md_key] * power
      mid = kline[ma_key]
      lower = kline[ma_key] - kline[md_key] * power

      kline = Map.take(kline, ["id", "datetime", "updated_at", "open", "close", "high", "low"])
      Map.merge(kline, %{"upper" => upper, "mid" => mid, "lower" => lower})
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