defmodule Strategy.TrendFollowing.Breakout.DonchainChannel do
  @moduledoc """
  唐奇安通道
  """
  use Strategy.TrendFollowing.System

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
end