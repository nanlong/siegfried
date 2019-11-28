defmodule TrendTracker.Backtest.Client do

  import TrendTracker.Helper, only: [file_log: 2, to_float: 2, float_to_binary: 2]
  import TrendTracker.Exchange.Helper, only: [contract_size: 1, futures_profit: 5]

  def submit_order(_client_name, {from, {:open, trend, trade}}, volume, state) do
    file_log("backtest", "#{String.slice(trade["datetime"], 0..24)} #{state[:symbol]} #{direction(from, :open, trend)}，价格：#{format(trade["price"], 8)}，合约张数：#{format(volume)}")
    {:ok, %{"price" => trade["price"], "volume" => volume, "filled_cash_amount" => 0}}
  end

  def submit_order(_client_name, {from, {:close, trend, trade}}, volume, state) do
    file_log("backtest", "#{String.slice(trade["datetime"], 0..24)} #{state[:symbol]} #{direction(from, :close, trend)}，价格：#{format(trade["price"], 8)}，合约张数：#{format(volume)}")
    balance = GenServer.call(state[:systems][:client], {:balance, state[:symbol]})
    {_symbol, position} = GenServer.call(state[:systems][:bankroll], :position)
    contract_size = contract_size(state[:symbol])
    first_order = List.first(position.orders)
    amount = to_float(balance / first_order.price, 8)

    hedge_price = first_order.price
    hedge_volume = to_float(balance / contract_size, 0)
    hedge_profit = futures_profit(:short, hedge_volume, contract_size, hedge_price, trade["price"])

    order_profit = fn order -> futures_profit(trend, order.volume, contract_size, order.price, trade["price"]) end
    trade_profit = position.orders |> Enum.map(order_profit) |> Enum.sum()

    filled_cash_amount = trade["price"] * (amount + hedge_profit + trade_profit)
    diff = filled_cash_amount - balance

    total_balance = GenServer.call(state[:systems][:client], :balance)
    current_balance = total_balance + diff
    file_log("backtest", "#{state[:symbol]} 盈利情况，原有资金：#{format(total_balance, 2)}，当前资金：#{format(current_balance, 2)}，变化：#{if diff >= 0, do: "+"}#{format(diff, 2)} #{if diff >= 0, do: "+"}#{format(diff / total_balance * 100, 2)}%")

    {:ok, %{"price" => trade["price"], "volume" => volume, "filled_cash_amount" => filled_cash_amount}}
  end

  defp direction(system, action, trend) do
    case {system, action, trend} do
      {:breakout, :open, :long} -> "开仓做多"
      {:bankroll, :open, :long} -> "加仓做多"
      {:breakout, :open, :short} -> "开仓做空"
      {:bankroll, :open, :short} -> "加仓做空"
      {:breakout, :close, :long} -> "平多止盈"
      {:bankroll, :close, :long} -> "平多止损"
      {:breakout, :close, :short} -> "平空止盈"
      {:bankroll, :close, :short} -> "平空止损"
    end
  end

  defp format(float, decimals \\ 0) do
    float_to_binary(float, decimals)
  end
end