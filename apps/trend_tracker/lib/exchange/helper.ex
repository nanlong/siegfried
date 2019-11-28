defmodule TrendTracker.Exchange.Helper do

  # 一张合约价值，单位美元
  def contract_size(symbol) do
    if symbol |> String.downcase() |> String.starts_with?("btc"), do: 100, else: 10
  end

  def futures_profit(trend, contract_count, contract_size, hold_price, new_price) do
    case trend do
      :long -> (1 / hold_price - 1 / new_price) * contract_count * contract_size
      :short -> (1 / new_price - 1 / hold_price) * contract_count * contract_size
    end
  end

  def seconds(period) do
    case period do
      "1min" -> 60
      "5min" -> 60 * 5
      "15min" -> 60 * 15
      "30min" -> 60 * 30
      "60min" -> 60 * 60
      "1day" -> 60 * 60 * 24
      "1week" -> 60 * 60 * 24 * 7
    end
  end

  def datetime_to_timestamp(datetime) do
    datetime
    |> NaiveDateTime.from_iso8601!()
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.to_unix()
  end

  def timestamp_to_datetime(timestamp) do
    timestamp
    |> DateTime.from_unix!()
    |> DateTime.to_iso8601()
  end

  def timestamp_to_local(timestamp) do
    timestamp
    |> DateTime.from_unix!()
    |> DateTime.to_iso8601()
    |> Timex.parse!("{ISO:Extended}")
    |> Timex.Timezone.convert("Asia/Shanghai")
    |> DateTime.to_string()
  end
end