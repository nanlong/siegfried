defmodule Siegfried do
  alias Siegfried.Exchange
  alias TrendTracker.Exchange.Huobi.History, as: HuobiHistory

  def list_klines(exchange, symbol, period, from \\ nil, to \\ nil) do
    klines = Exchange.list_klines(exchange, symbol, period, from, to)

    Enum.map(klines, fn kline ->
      %{
        "exchange" => kline.exchange,
        "symbol" => kline.symbol,
        "period" => kline.period,
        "datetime" => kline.datetime,
        "timestamp" => kline.timestamp,
        "open" => kline.open,
        "close" => kline.close,
        "low" => kline.low,
        "high" => kline.high,
        "updated_at" => kline.updated_at,
      }
    end)
  end

  def huobi_history(market, symbol, period) do
    {:ok, pid} = HuobiHistory.start_link(market, symbol, period)

    HuobiHistory.on_message(pid, fn message ->
      attrs = Exchange.kline_from_huobi(symbol, period, message)
      Exchange.create_kline(attrs)
    end)

    HuobiHistory.start(pid)
  end
end
