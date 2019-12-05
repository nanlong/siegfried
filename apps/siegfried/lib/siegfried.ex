defmodule Siegfried do

  alias Siegfried.Exchange
  alias Siegfried.Exchange.Kline
  alias TrendTracker.Exchange.Huobi.History, as: HuobiHistory
  alias TrendTracker.Exchange.Okex.History, as: OkexHistory


  def get_cache(name, default \\ nil) do
    key = to_string(name)

    case Siegfried.TrendTracker.get_cache(key) do
      nil ->
        if default do
          {:ok, _} = Siegfried.TrendTracker.set_cache(key, default)
          default
        end

      value -> value
    end
  end

  defdelegate set_cache(key, value), to: Siegfried.TrendTracker
  defdelegate delete_cache(key), to: Siegfried.TrendTracker
  defdelegate delete_all_cache, to: Siegfried.TrendTracker

  defdelegate transform_timestamp(timestamp), to: Kline

  def first_kline(exchange, symbol, period) do
    exchange |> list_klines(symbol, period) |> List.first()
  end

  def last_kline(exchange, symbol, "1min") do
    kline = Exchange.last_kline(exchange, symbol, "1min")
    kline_from_siegfried(kline)
  end
  def last_kline(exchange, symbol, period) do
    exchange |> list_klines(symbol, period) |> List.last()
  end

  def get_kline(exchange, symbol, period, from, cache) do
    kline = Exchange.get_kline(exchange, symbol, period, from, cache)

    if kline do
      %{
        "timestamp" => kline.timestamp,
        "datetime" => kline.datetime,
        "open" => kline.open,
        "close" => kline.close,
        "low" => kline.low,
        "high" => kline.high
      }
    end
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

  @moduledoc """

  ## Examples

    iex> Siegfried.okex_history(:spot, "btc-usdt", "1week")
    iex> Siegfried.okex_history(:swap, "btc-usd-swap", "1week")

  """
  def okex_history(market, symbol, period) do
    {:ok, pid} = OkexHistory.start_link(market, symbol, period)

    OkexHistory.on_message(pid, fn message ->
      attrs = Exchange.kline_from_okex(symbol, period, message)
      Exchange.create_kline(attrs)
    end)

    OkexHistory.start(pid)
  end
end
