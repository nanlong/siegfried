defmodule Strategy.TrendFollowing.Breakout.KeltnerChannel do
  @moduledoc """
  肯特钠通道
  """
  use Strategy.TrendFollowing.System

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
    |> Enum.map(fn
      %{^ema_key => _, ^atr_key => _} = kline ->
        upper = kline[ema_key] + kline[atr_key] * power
        mid = kline[ema_key]
        lower = kline[ema_key] - kline[atr_key] * power

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
end