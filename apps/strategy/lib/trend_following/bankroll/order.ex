defmodule Strategy.TrendFollowing.Bankroll.Order do
  @moduledoc """
  持仓订单
  """

  @type order_price :: float
  @type order_volume :: float
  @type order_created_at :: DateTime.t()

  defstruct [:price, :volume, :created_at]

  def new(price, volume) do
    %__MODULE__{
      price: price,
      volume: volume,
      created_at: now(),
    }
  end

  def now do
    :millisecond
    |> :os.system_time()
    |> DateTime.from_unix!(:millisecond)
  end
end