defmodule Siegfried.Exchange do
  @moduledoc """
  The Exchange context.
  """

  import Ecto.Query, warn: false
  alias Siegfried.Repo

  alias Siegfried.Exchange.Kline


  def get_kline(exchange, symbol, period, from) do
    day_seconds = 60 * 60 * 24
    week_seconds = day_seconds * 7
    kline = list_klines(exchange, symbol, period, from - week_seconds, from) |> List.last()

    if kline do
      kline_1min = list_klines(exchange, symbol, "1min", from, from) |> List.first()
      close = if kline_1min && kline_1min.timestamp < kline.timestamp + day_seconds, do: kline_1min.timestamp, else: kline.close
      data = list_klines(exchange, symbol, "1min", kline.timestamp, from)
      low = data |> Enum.map(&(&1.low)) |> Enum.min()
      high = data |> Enum.map(&(&1.high)) |> Enum.max()
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
      to = if not is_nil(kline) and kline.timestamp > from, do: kline.timestamp, else: to
      spot_klines = list_klines(exchange, symbol, period, from, to)
      Enum.slice(spot_klines, 0..-2) ++ klines
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
