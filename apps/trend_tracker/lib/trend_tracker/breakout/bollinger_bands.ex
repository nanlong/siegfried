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
    |> Enum.map(fn
      %{^ma_key => _, ^md_key => _} = kline ->
        upper = kline[ma_key] + kline[md_key] * power
        mid = kline[ma_key]
        lower = kline[ma_key] - kline[md_key] * power

        Map.merge(take_kline(kline), %{"upper" => upper, "mid" => mid, "lower" => lower})

      kline ->
        take_kline(kline)
    end)
  end

  def breakout(state) do
    case klines(state) do
      [%{"upper" => long_open, "lower" => short_open}, %{"mid" => close}] ->
        %{long_open: long_open, long_close: close, short_open: short_open, short_close: close}

      _ -> nil
    end
  end

  def signal(trade, state) do
    trend = get_trend(state)
    position = get_position(state)

    case breakout(state) do
      %{long_open: long_open, long_close: long_close, short_open: short_open, short_close: short_close} ->
        cond do
          position.status == :filled && position.trend == :long && trade["price"] <= long_close ->
            {:close, position.trend, trade}

          position.status == :filled && position.trend == :short && trade["price"] >= short_close ->
            {:close, position.trend, trade}

          position.status == :empty && trend == :long && trade["price"] >= long_open ->
            {:open, trend, trade}

          position.status == :empty && trend == :short && trade["price"] <= short_open ->
            {:open, trend, trade}

          true ->
            {:wait, trend, trade}
        end

      _ ->
        {:wait, trend, trade}
    end
  end
end