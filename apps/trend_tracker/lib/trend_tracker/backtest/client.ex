defmodule TrendTracker.Backtest.Client do

  use GenServer

  import TrendTracker.Helper, only: [file_log: 2, to_float: 2, float_to_binary: 2]
  import TrendTracker.Exchange.Helper, only: [contract_size: 1, futures_profit: 5]

  def start_link(opts \\ []) do
    state = %{
      balance: opts[:balance],
      symbols: opts[:symbols],
    }
    GenServer.start_link(__MODULE__, state, opts)
  end

  def init(state) do
    symbols_balance = Map.new(state[:symbols], fn symbol -> {symbol, state[:balance] / length(state[:symbols])} end)
    {:ok, Map.merge(state, %{symbols_balance: symbols_balance})}
  end

  def handle_call(:balance, _from, state) do
    {:reply, state[:balance], state}
  end

  def handle_call({:balance, symbol}, _from, state) do
    {:reply, state[:symbols_balance][symbol], state}
  end

  def handle_call({:profit, symbol, balance}, _from, state) do
    # 更新资金总量
    state = %{state | balance: state[:balance] + (balance - state[:symbols_balance][symbol])}

    # 更新对应币种的资金量
    state = %{state | symbols_balance: %{state[:symbols_balance] | symbol => 0}}

    {:reply, state, state}
  end

  def handle_call({system, :open, trend, trade, volume, opts}, _from, state) do
    file_log("backtest.log", "#{String.slice(trade["datetime"], 0..24)} #{opts[:symbol]} #{direction(system, :open, trend)}，价格：#{format(trade["price"], 8)}，合约张数：#{format(volume)}")
    {:reply, %{"price" => trade["price"], "volume" => volume}, state}
  end

  def handle_call({system, :close, trend, trade, volume, opts}, _from, state) do
    file_log("backtest.log", "#{String.slice(trade["datetime"], 0..24)} #{opts[:symbol]} #{direction(system, :close, trend)}，价格：#{format(trade["price"], 8)}，合约张数：#{format(volume)}")
    balance = state[:symbols_balance][opts[:symbol]]
    position = opts[:position]
    contract_size = contract_size(opts[:symbol])
    first_order = List.first(position.orders)
    amount = to_float(balance / first_order.price, 8)

    hedge_price = first_order.price
    hedge_volume = to_float(balance / contract_size, 0)
    hedge_profit = futures_profit(:short, hedge_volume, contract_size, hedge_price, trade["price"])

    order_profit = fn order -> futures_profit(trend, order.volume, contract_size, order.price, trade["price"]) end
    trade_profit = position.orders |> Enum.map(order_profit) |> Enum.sum()

    filled_cash_amount = trade["price"] * (amount + hedge_profit + trade_profit)
    diff = filled_cash_amount - balance

    total_balance = state[:balance]
    current_balance = total_balance + diff
    file_log("backtest.log", "#{opts[:symbol]} 盈利情况，原有资金：#{format(total_balance, 2)}，当前资金：#{format(current_balance, 2)}，变化：#{if diff >= 0, do: "+"}#{format(diff, 2)} #{if diff >= 0, do: "+"}#{format(diff / total_balance * 100, 2)}%")

    {:reply, %{"filled_cash_amount" => filled_cash_amount}, state}
  end

  def submit_order(client_name, {from, {:open, trend, trade}}, volume, state) do
    {:ok, GenServer.call(client_name, {from, :open, trend, trade, volume, state})}
  end

  def submit_order(client_name, {from, {:close, trend, trade}}, volume, state) do
    {_symbol, position} = GenServer.call(state[:systems][:bankroll], :position)
    {:ok, GenServer.call(client_name, {from, :close, trend, trade, volume, Map.merge(state, %{position: position})})}
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