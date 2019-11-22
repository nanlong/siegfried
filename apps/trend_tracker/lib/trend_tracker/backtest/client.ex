defmodule TrendTracker.Backtest.Client do

  alias TrendTracker.Helper, as: TrendTrackerHelper
  alias TrendTracker.Exchange.Huobi.Helper, as: HuobiHelper
  alias Siegfried.Exchange.Kline

  require Logger

  def submit_order(_client_name, :open, trend, price, volume, timestamp, state) do
    direction = if trend == :long, do: "做多", else: "做空"
    datetime = Kline.transform_timestamp(timestamp)
    TrendTrackerHelper.file_log("#{String.slice(datetime, 0..24)} #{state[:symbol]} #{direction}，价格：#{format(price, 8)}，合约张数：#{format(volume)}")
    {:ok, %{"price" => price, "volume" => volume, "filled_cash_amount" => 0}}
  end

  def submit_order(_client_name, :close, trend, price, volume, timestamp, state) do
    direction = if trend == :long, do: "平多", else: "平空"
    datetime = Kline.transform_timestamp(timestamp)
    TrendTrackerHelper.file_log("#{String.slice(datetime, 0..24)} #{state[:symbol]} #{direction}，价格：#{format(price, 8)}，合约张数：#{format(volume)}")
    balance = GenServer.call(state[:systems][:client], {:balance, state[:symbol]})
    {_symbol, position} = GenServer.call(state[:systems][:bankroll], :position)
    contract_size = HuobiHelper.contract_size(state[:symbol])
    first_order = List.first(position.orders)
    amount = TrendTrackerHelper.to_float(balance / first_order.price, 8)

    hedge_price = first_order.price
    hedge_volume = TrendTrackerHelper.to_float(balance / contract_size, 0)
    hedge_profit = HuobiHelper.futures_profit(:short, hedge_volume, contract_size, hedge_price, price)

    order_profit = fn order -> HuobiHelper.futures_profit(trend, order.volume, contract_size, order.price, price) end
    trade_profit = position.orders |> Enum.map(order_profit) |> Enum.sum()

    filled_cash_amount = price * (amount + hedge_profit + trade_profit)

    diff = filled_cash_amount - balance
    TrendTrackerHelper.file_log("#{state[:symbol]} 盈利情况，原有：#{format(balance, 8)}，现在：#{format(filled_cash_amount, 8)}，变化：#{if diff >= 0, do: "+"}#{format(diff, 8)}")

    {:ok, %{"price" => price, "volume" => volume, "filled_cash_amount" => filled_cash_amount}}
  end

  defp format(float, decimals \\ 0) do
    TrendTrackerHelper.float_to_binary(float, decimals)
  end
end