defmodule TrendTracker.Breakout.DonchainChannel do
  @moduledoc """
  唐奇安通道
  """
  use TrendTracker.System

  def default do
    [upper: 20, lower: 10]
  end

  def indicators(state) do
    upper = get_params(state, :upper)
    lower = get_params(state, :lower)

    [
      [{:max, "high", upper}, rename: "upper_long"],
      [{:min, "low", lower}, rename: "lower_long"],
      [{:min, "low", upper}, rename: "lower_short"],
      [{:max, "high", lower}, rename: "upper_short"],
    ]
  end

  def signal(trade, state) do
    [pre_kline, _cur_kline] = klines(state)
    trend = get_trend(state)
    position = get_position(state)

    cond do
      position.status == :filled && position.trend == :long && trade["price"] < pre_kline["lower_long"] ->
        {:close, position.trend, trade}

      position.status == :filled && position.trend == :short && trade["price"] > pre_kline["upper_short"] ->
        {:close, position.trend, trade}

      position.status == :empty && trend == :long && trade["price"] > pre_kline["upper_long"] ->
        {:open, trend, trade}

      position.status == :empty && trend == :short && trade["price"] < pre_kline["lower_short"] ->
        {:open, trend, trade}

      true ->
        {:wait, trend, trade}
    end
  end
end