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
  """
  use TrendTracker.System

  alias TrendTracker.Bankroll.Position

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
  def update_position(%{position: %{balance: balance, status: :empty} = position} = state) when is_float(balance) do
    [pre_kline, cur_kline] = klines(state[:klines])
    contract_size = TrendTracker.Exchange.Huobi.Helper.contract_size(state[:symbol])
    position = Position.update_when_empty(position, pre_kline["atr"], cur_kline["close"], contract_size)
    {:ok, %{state | position: position}}
  end
  # 持仓状态下，什么也不做
  def update_position(state), do: {:ok, state}

  def signal(trade, %{position: %{status: :empty} = position}) do
    {:wait, position.trend, trade}
  end
  def signal(trade, %{position: position}) do
    cond do
      position.trend == :long && trade["price"] < position.close_price ->
        {:close, position.trend, trade}

      position.trend == :short && trade["price"] > position.close_price ->
        {:close, position.trend, trade}

      position.status == :hold && position.trend == :long && trade["price"] > position.open_price ->
        {:open, position.trend, trade}

      position.status == :hold && position.trend == :short && trade["price"] < position.open_price ->
        {:open, position.trend, trade}

      true ->
        {:wait, position.trend, trade}
    end
  end

  def handle_call(:balance, _from, state) do
    {:reply, {:ok, state[:position].balance}, state}
  end

  def handle_call({:balance, balance}, _from, state) do
    position = Position.update(state[:position], :balance, balance)
    {:reply, {:ok, position}, %{state | position: position}}
  end

  def handle_call(:position, _from, state) do
    {:reply, {:ok, state[:position]}, state}
  end

  def handle_call({:open_position, trend, price, volume}, _from, state) do
    position = Position.open(state[:position], trend, price, volume)
    {:reply, {:ok, position}, %{state | position: position}}
  end

  def handle_call(:close_position, _from, state) do
    position = Position.close(state[:position])
    {:reply, {:ok, position}, %{state | position: position}}
  end
end