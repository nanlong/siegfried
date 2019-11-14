defmodule Siegfried.Exchange do
  @moduledoc """
  The Exchange context.
  """

  import Ecto.Query, warn: false
  alias Siegfried.Repo

  alias Siegfried.Exchange.Kline

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
    kline = List.first(klines)

    # 合约K线可能比较少，使用现货的K线数据
    if exchange == "huobi" and String.contains?(symbol, "_") and not is_nil(kline) and kline.timestamp > from do
      kline = List.first(klines)
      currency = symbol |> String.split("_") |> List.first() |> String.downcase()
      symbol = "#{currency}usdt"
      spot_klines = list_klines(exchange, symbol, period, from, kline.timestamp)
      spot_klines ++ Enum.slice(klines, 1..-1)
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
