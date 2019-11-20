defmodule TrendTracker.Breakout.DonchainChannel do
  @moduledoc """
  唐奇安通道
  """
  use TrendTracker.System

  def default do
    [fast: 10, slow: 20]
  end

  def indicators(state) do
    fast = get_params(state, :fast)
    slow = get_params(state, :slow)

    [
      # 10日通道
      [{:max, "high", fast}, rename: "max_high_fast"],
      [{:min, "low", fast}, rename: "min_low_fast"],

      # 20日通道
      [{:max, "high", slow}, rename: "max_high_slow"],
      [{:min, "low", slow}, rename: "min_low_slow"],
    ]
  end

  def breakout(state) do
    case klines(state) do
      [%{"max_high_slow" => long_open, "min_low_slow" => short_open, "max_high_fast" => short_close, "min_low_fast" => long_close}, _cur_kline] ->
        %{long_open: long_open, long_close: long_close, short_open: short_open, short_close: short_close}

      _ -> nil
    end
  end

  def signal(trade, state) do
    trend = get_trend(state)
    position = get_position(state)

    case breakout(state) do
      %{long_open: long_open, long_close: long_close, short_open: short_open, short_close: short_close} ->
        cond do
          position.status == :filled && position.trend == :long && trade["price"] <= long_close  ->
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