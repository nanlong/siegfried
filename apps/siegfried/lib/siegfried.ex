defmodule Siegfried do
  alias Siegfried.Exchange
  alias TrendTracker.Exchange.Huobi.History, as: HuobiHistory

  def first_kline(exchange, symbol, period) do
    exchange |> list_klines(symbol, period) |> List.first()
  end

  def get_kline(exchange, symbol, period, from) do
    kline = Exchange.get_kline(exchange, symbol, period, from)
    if kline, do: %{"id" => kline.timestamp, "open" => kline.open, "close" => kline.close, "low" => kline.low, "high" => kline.high}
  end

  def list_klines(exchange, symbol, period, from \\ nil, to \\ nil) do
    klines = Exchange.list_klines(exchange, symbol, period, from, to)
    Enum.map(klines, &kline_from_siegfried/1)
  end

  def kline_from_siegfried(kline) do
    keys = [:exchange, :symbol, :period, :datetime, :timestamp, :open, :close, :low, :high, :updated_at]
    data = kline |> Map.from_struct() |> Map.take(keys)
    for {k, v} <- data, into: %{}, do: {to_string(k), v}
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
