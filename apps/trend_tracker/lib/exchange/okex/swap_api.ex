defmodule TrendTracker.Exchange.Okex.SwapAPI do
  alias TrendTracker.Exchange.Okex.Service, as: OkexService

  @doc """
  获取合约信息
  """
  def get_instruments(service) do
    path = "/api/swap/v3/instruments"
    speed_limit = 2 / 20
    OkexService.request(service, :get, path, speed_limit)
  end

  @doc """
  获取当前限价
  """
  def get_price_limit(service, instrument_id) do
    path = "/api/swap/v3/instruments/#{instrument_id}/price_limit"
    speed_limit = 2 / 20
    OkexService.request(service, :get, path, speed_limit)
  end

  @doc """
  获取合约标记价格
  """
  def get_mark_price(service, instrument_id) do
    path = "/api/swap/v3/instruments/#{instrument_id}/mark_price"
    speed_limit = 2 / 20
    OkexService.request(service, :get, path, speed_limit)
  end

  @doc """
  所有币种合约账户信息
  """
  def get_accounts(service) do
    path = "/api/swap/v3/accounts"
    speed_limit = 10
    OkexService.request(service, :get, path, speed_limit)
  end

  @doc """
  单个币种合约账户信息
  """
  def get_accounts(service, instrument_id) do
    path = "/api/swap/v3/#{instrument_id}/accounts"
    speed_limit = 2 / 20
    OkexService.request(service, :get, path, speed_limit)
  end

  @doc """
  所有合约持仓信息
  """
  def get_position(service) do
    path = "/api/swap/v3/position"
    speed_limit = 10
    OkexService.request(service, :get, path, speed_limit)
  end

  @doc """
  单个合约持仓信息
  """
  def get_position(service, instrument_id) do
    path = "/api/swap/v3/#{instrument_id}/position"
    speed_limit = 2 / 20
    OkexService.request(service, :get, path, speed_limit)
  end

  @doc """
  获取某个合约的用户配置
  """
  def get_settings(service, instrument_id) do
    path = "/api/swap/v3/accounts/#{instrument_id}/settings"
    speed_limit = 2 / 5
    OkexService.request(service, :get, path, speed_limit)
  end

  @doc """
  设定某个合约的杠杆
  """
  def set_leverage(service, instrument_id, leverage, side) do
    path = "/api/swap/v3/accounts/#{instrument_id}/leverage"
    speed_limit = 2 / 5
    body = %{leverage: leverage, side: side}
    OkexService.request(service, :post, path, speed_limit, body: body)
  end

  @doc """
  下单
  """
  def submit_order(service, instrument_id, type, price, size, opts \\ []) do
    path = "/api/swap/v3/order"
    speed_limit = 2 / 40
    body = %{instrument_id: instrument_id, type: type, price: price, size: size}
    body = OkexService.optional_body(body, opts, [:client_oid, :order_type, :match_price])
    OkexService.request(service, :post, path, speed_limit, body: body)
  end

  @doc """
  撤单
  """
  def cancel_order(service, instrument_id, opts \\ []) do
    path = "/api/swap/v3/cancel_order/#{instrument_id}/#{OkexService.choose_one(opts, [:order_id, :client_oid])}"
    speed_limit = 2 / 40
    OkexService.request(service, :post, path, speed_limit)
  end

  @doc """
  获取订单信息
  """
  def get_order_info(service, instrument_id, opts \\ []) do
    path = "/api/swap/v3/orders/#{instrument_id}/#{OkexService.choose_one(opts, [:order_id, :client_oid])}"
    speed_limit = 2 / 40
    OkexService.request(service, :get, path, speed_limit)
  end
end