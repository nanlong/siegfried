defmodule Strategy.GridTrading.Kline do
  @moduledoc """

  {:ok, pid} = Strategy.GridTrading.Kline.start_link(exchange: "huobi", symbol: "eosusdt", period: "15min", source: Siegfried, indicators: [period: 96])
  {_, [_, kline]} = GenServer.call(pid, :klines)
  Strategy.GridTrading.Kline.profit(10, kline)
  """

  use Strategy.System

  def default do
    [period: 20]
  end

  def indicators(state) do
    period = get_params(state, :period)

    [
      :tr,
      [{:atr, period}, rename: "atr"],
    ]
  end

  def profit(amount, kline) do
    charge = 0.998
    buy_price = Float.round(kline["close"] - kline["atr"], 4)
    sell_price = Float.round(kline["close"] + kline["atr"], 4)
    volume = Float.floor(amount / buy_price * charge, 4)
    sell_amount = Float.floor(volume * sell_price * charge, 4)
    {buy_price, sell_price, volume, Float.floor(sell_amount - amount, 4)}
  end
end