defmodule TrendTracker.Exchange.Huobi do

  def kline(exchange, symbol, period, data) do

    %{
      "exchange" => exchange,
      "symbol" => symbol,
      "period" => period,
      "datetime" => TrendTracker.Helper.transform_timestamp(data["id"]),
      "timestamp" => data["id"],
      "open" => data["open"],
      "close" => data["close"],
      "low" => data["low"],
      "high" => data["high"],
      "updated_at" => NaiveDateTime.utc_now(),
    }
  end
end