defmodule TrendTracker.Bankroll.Turtle do
  @moduledoc """
  资金管理海龟系统

  趋势 trend
    - 多头 long
    - 空头 short

  仓位状态 position.status
    - 空仓 empty
    - 持仓 hold
    - 满仓 full

  todo:
    1. 空仓状态下，更新仓位大小
    2. 持仓状态下，更新加仓和清仓价格

  {:ok, pid} = TrendTracker.Bankroll.Turtle.start_link(exchange: "huobi", symbol: "BTC_CQ", period: "1day", source: Siegfried)
  """
  use TrendTracker.System

  alias TrendTracker.Bankroll.Position
  alias TrendTracker.Exchange.Huobi.Helper, as: HuobiHelper

  def default do
    [period: 20, power: 0.5, atr_ratio: 0.01, atr_cost: 1]
  end

  def indicators(state) do
    period = get_params(state, :period)

    [
      :tr,
      [{:atr, period}, rename: "atr"],
    ]
  end

  def init_before(state) do
    state = super(state)
    power = get_params(state, :power)
    atr_ratio = get_params(state, :atr_ratio)
    atr_cost = get_params(state, :atr_cost)
    Map.merge(state, %{position: Position.new(power, atr_ratio, atr_cost)})
  end

  # 初始化后，更新仓位信息
  def init_after(state) do
    {:ok, state} = update_position(state)
    state
  end

  # 有新的K线，更新仓位信息
  def kline_after(state) do
    {:ok, state} = update_position(state)
    state
  end

  # 空仓状态下，更新仓位大小
  def update_position(%{position: %{status: :empty} = position} = state) do
    symbol = state[:symbol]

    case klines(state) do
      [%{"atr" => _} = pre_kline, %{"close" => _} = cur_kline] ->
        contract_size = HuobiHelper.contract_size(state[:symbol])
        balance = GenServer.call(state[:systems][:account], :balance)
        {^symbol, trend} = GenServer.call(state[:systems][:trend], :trend)
        {^symbol, price} = GenServer.call(state[:systems][:breakout], :breakout)

        # 更新开仓价格
        position = Position.update(position, :open_price, price[String.to_atom("#{trend}_open")])
        # 更新一仓规模
        position = Position.update_volume(position, balance, pre_kline["atr"], cur_kline["close"], contract_size)

        Logger.debug "Turtpe update position: #{inspect(position)}"
        {:ok, %{state | position: position}}

      _ ->
        {:ok, state}
    end
  end
  # 持仓状态下，什么也不做
  def update_position(state), do: state

  def signal(trade, %{position: %{status: :empty} = position}) do
    {:wait, position.trend, trade}
  end
  def signal(trade, %{position: %{close_price: close_price, open_price: open_price} = position}) when is_float(close_price) and is_float(open_price) do
    cond do
      position.trend == :long && trade["price"] < close_price ->
        {:close, position.trend, trade}

      position.trend == :short && trade["price"] > close_price ->
        {:close, position.trend, trade}

      position.status == :hold && position.trend == :long && trade["price"] > open_price ->
        {:open, position.trend, trade}

      position.status == :hold && position.trend == :short && trade["price"] < open_price ->
        {:open, position.trend, trade}

      true ->
        {:wait, position.trend, trade}
    end
  end
  def signal(trade, state) do
    raise("获取信号时，资金管理系统数据异常：\nstate: #{inspect(state)}}\ntrade: #{inspect(trade)}")
  end

  def handle_call(:position, _from, state) do
    {:reply, {state[:symbol], state[:position]}, state}
  end

  def handle_call({:open_position, trend, price, volume}, _from, state) do
    position = Position.open(state[:position], trend, price, volume)
    {:reply, {state[:symbol], position}, %{state | position: position}}
  end

  def handle_call(:close_position, _from, state) do
    position = Position.close(state[:position])
    {:reply, {state[:symbol], position}, %{state | position: position}}
  end
end