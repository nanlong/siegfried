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
        contract_size = ExchangeHelper.contract_size(state[:symbol])
        balance = GenServer.call(state[:systems][:client], :balance)
        {^symbol, trend} = GenServer.call(state[:systems][:trend], :trend)
        {^symbol, price} = GenServer.call(state[:systems][:breakout], :breakout)

        # 更新整体趋势
        position = Position.update(position, :trend, trend)
        # 更新开仓价格
        position = Position.update(position, :open_price, price[String.to_atom("#{trend}_open")])
        # 更新合约张数
        position = Position.update_volume(position, balance, pre_kline["atr"], cur_kline["close"], contract_size)

        Logger.debug "Turtpe update position: #{inspect(position)}"
        {:ok, %{state | position: position}}

      _ ->
        {:ok, state}
    end
  end
  # 持仓状态下，什么也不做
  def update_position(state), do: {:ok, state}

  def signal(trade, %{position: %{status: :empty} = position}) do
    {:wait, position.trend, trade}
  end
  def signal(trade, %{position: %{close_price: close_price, open_price: open_price} = position}) when is_float(close_price) and is_float(open_price) do
    cond do
      Position.long?(position) && trade["price"] <= close_price ->
        Logger.warn("平多止损, #{trade["price"]} <= #{close_price}")
        {:close, position.trend, trade}

      Position.short?(position) && trade["price"] >= close_price ->
        Logger.warn("平空止损, #{trade["price"]} >= #{close_price}")
        {:close, position.trend, trade}

      Position.hold?(position) && Position.long?(position) && trade["price"] >= open_price ->
        Logger.warn("加仓做多, #{trade["price"]} >= #{open_price}")
        {:open, position.trend, trade}

      Position.hold?(position) && Position.short?(position) && trade["price"] <= open_price ->
        Logger.warn("加仓做空, #{trade["price"]} <= #{open_price}")
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

  def handle_call({:open, trend, price, volume}, _from, state) do
    position = Position.open(state[:position], trend, price, volume)
    {:reply, {state[:symbol], position}, %{state | position: position}}
  end

  def handle_call(:close, _from, state) do
    position = Position.close(state[:position])
    {:reply, {state[:symbol], position}, %{state | position: position}}
  end
end