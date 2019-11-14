defmodule Siegfried.Exchange do
  @moduledoc """
  The Exchange context.
  """

  import Ecto.Query, warn: false
  alias Siegfried.Repo

  alias Siegfried.Exchange.Kline

  def list_klines(exchange, symbol, period) do
    Kline
    |> where([k], k.exchange == ^exchange)
    |> where([k], k.symbol == ^symbol)
    |> where([k], k.period == ^period)
    |> order_by(asc: :timestamp)
    |> Repo.all()
  end

  def create_kline(attrs \\ %{}) do
    kline = Repo.get_by(Kline, exchange: attrs["exchange"], symbol: attrs["symbol"], period: attrs["period"], timestamp: attrs["timestamp"])

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
