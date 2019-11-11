defmodule TrendTracker.Bankroll.Position do
  @doc """
  仓位信息
  """

  alias TrendTracker.Bankroll.Order

  @typedoc "资金量"
  @type position_balance :: float | nil

  @typedoc "仓位状态"
  @type position_status :: :empty | :hold | :full

  @typedoc "开仓时的趋势情况"
  @type position_trend :: :long | :short | nil

  @typedoc "加仓幅度，与atr计算"
  @type position_power :: float | nil

  @typedoc "用于计算一仓合约张数"
  @type position_atr :: float

  @typedoc "每一个atr涨幅对应的资金百分比"
  @type position_atr_ratio :: float

  @typedoc "每一点atr对应的美元价值"
  @type position_atr_cost :: float

  @typedoc "开仓价"
  @type position_open_price :: float | nil

  @typedoc "止损价"
  @type position_close_price :: float | nil

  @typedoc "最大持仓数量"
  @type position_max :: integer

  @typedoc "每仓合约张数"
  @type position_volume :: integer | nil

  @typedoc "开仓订单"
  @type position_orders :: list

  defstruct [:balance, :status, :trend, :power, :atr, :atr_ratio, :atr_cost, :open_price, :close_price, :max, :volume, :orders]

  def new(power, atr_ratio, atr_cost) do
    %__MODULE__{
      balance: nil,
      status: :empty,
      trend: nil,
      power: power,
      atr: nil,
      atr_ratio: atr_ratio,
      atr_cost: atr_cost,
      open_price: nil,
      close_price: nil,
      max: 4,
      volume: nil,
      orders: [],
    }
  end

  @doc """
  更新
  """
  def update(position, field, value) do
    %{position | field => value}
  end

  def update_when_empty(position, atr, price, contract_size) do
    volume = trunc((position.balance * position.atr_ratio) / (atr * position.atr_cost) * price / contract_size)

    position
    |> update(:atr, atr)
    |> update(:volume, volume)
  end

  @doc """
  开仓
  """
  def open(position, trend, price, volume) do
    order = Order.new(price, volume)
    orders = position.orders ++ [order]
    count = length(orders)
    status = if count >= position.max, do: :full, else: :hold
    average_price = orders |> Enum.map(&(&1.price)) |> Enum.sum() |> Kernel./(count)
    open_diff = position.atr * position.power
    close_diff = position.atr * position.max * position.power / count

    {open_price, close_price} = case position.trend || trend do
      :long -> {order.price + open_diff, average_price - close_diff}
      :short -> {order.price - open_diff, average_price + close_diff}
    end

    position
    |> update(:status, status)
    |> update(:trend, trend)
    |> update(:orders, orders)
    |> update(:open_price, open_price)
    |> update(:close_price, close_price)
  end

  @doc """
  清仓
  """
  def close(position) do
    position
    |> update(:status, :empty)
    |> update(:trend, nil)
    |> update(:orders, [])
    |> update(:open_price, nil)
    |> update(:close_price, nil)
  end

  @doc """
  当前持仓总量
  """
  def volume(position) do
    position.orders |> Enum.map(&(&1.volume)) |> Enum.sum()
  end
end