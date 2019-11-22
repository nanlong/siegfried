defmodule Siegfried.Exchange do
  @moduledoc """
  The Exchange context.
  """

  import Ecto.Query, warn: false

  alias Siegfried.Repo
  alias Siegfried.Exchange.Kline

  alias TrendTracker.Exchange.Huobi.Helper, as: HuobiHelper

  def last_kline(exchange, symbol, period) do
    query = from k in Kline,
      where: k.exchange == ^exchange,
      where: k.symbol == ^symbol,
      where: k.period == ^period,
      order_by: [desc: k.timestamp],
      limit: 1

    Repo.one(query)
  end

  def get_kline(exchange, symbol, period, kline_1min, cache) do
    from = kline_1min["timestamp"]
    kline = list_klines(exchange, symbol, period, from - HuobiHelper.seconds(period), from) |> List.last()

    if kline do
      data = Enum.filter(cache, fn item -> item["timestamp"] >= kline.timestamp and item["timestamp"] <= from end)
      %{"low" => low, "high" => high} = List.first(data)
      {low, high} = Enum.reduce(data, {low, high}, fn item, {low, high} -> {min(item["low"], low), max(item["high"], high)} end)
      close = if from - HuobiHelper.seconds(period) < kline.timestamp - HuobiHelper.seconds("1min"), do: kline_1min["close"], else: kline.close
      %{kline | close: close, low: low, high: high}
    end
  end

  def list_klines(exchange, symbol, period, from \\ nil, to \\ nil) do
    from = from || 0
    to = to || :os.system_time(:second)

    query = from k in Kline,
      where: k.exchange == ^exchange,
      where: k.symbol == ^symbol,
      where: k.period == ^period,
      where: k.timestamp >= ^from and k.timestamp <= ^to,
      order_by: [asc: k.timestamp]

    klines = Repo.all(query)

    # 合约K线可能比较少，使用现货的K线数据
    if exchange == "huobi" and String.contains?(symbol, "_") do
      kline = List.first(klines)
      currency = symbol |> String.split("_") |> List.first() |> String.downcase()
      symbol = "#{currency}usdt"
      to = if kline, do: kline.timestamp, else: to
      # 现货的周K线比合约K线少了86400秒，查询条件需要调整
      {from, to} = if period == "1week", do: {from - HuobiHelper.seconds("1day"), to - HuobiHelper.seconds("1day")}, else: {from, to}
      spot_klines = list_klines(exchange, symbol, period, from, to)

      spot_klines = if period == "1week" do
        Enum.map(spot_klines, fn kline ->
          # 修复周K线的时间戳，使之与合约K线一致
          timestamp = kline.timestamp + HuobiHelper.seconds("1day")
          %{kline | timestamp: timestamp, datetime: Kline.transform_timestamp(timestamp)}
        end)
      else
        spot_klines
      end

      if length(klines) > 0 do
        Enum.slice(spot_klines, 0..-2) ++ klines
      else
        spot_klines
      end
    else
      klines
    end
  end

  def create_kline(attrs \\ %{}) do
    kline = Repo.get_by(Kline,
      exchange: attrs["exchange"],
      symbol: attrs["symbol"],
      period: attrs["period"],
      timestamp: attrs["timestamp"]
    )

    case kline do
      nil -> Kline.changeset(%Kline{}, attrs)
      %{} -> Kline.changeset(kline, attrs)
    end
    |> Repo.insert_or_update()
  end

  def kline_from_huobi(symbol, period, data) do
    data
    |> Map.put("timestamp", data["id"])
    |> Map.merge(%{"exchange" => "huobi", "symbol" => symbol, "period" => period})
  end
end
