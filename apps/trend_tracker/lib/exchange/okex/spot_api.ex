defmodule TrendTracker.Exchange.Okex.SpotAPI do
  alias TrendTracker.Exchange.Okex.Service, as: OkexService

  @doc """
  获取币对信息
  """
  def get_instruments(service) do
    path = "/api/spot/v3/instruments"
    speed_limit = 2 / 20
    OkexService.request(service, :get, path, speed_limit)
  end

  @doc """
  币币账户信息
  """
  def get_accounts(service) do
    path = "/api/spot/v3/accounts"
    speed_limit = 2 / 20
    OkexService.request(service, :get, path, speed_limit)
  end

  @doc """
  单一币种账户信息
  """
  def get_accounts(service, currency) do
    path = "/api/spot/v3/accounts/#{currency}"
    speed_limit = 2 / 20
    OkexService.request(service, :get, path, speed_limit)
  end

  @doc """
  下单
  """
  def submit_order(service, instrument_id, type, side, opts \\ []) do
    path = "/api/spot/v3/orders"
    speed_limit = 2 / 100
    order_type = if type == "market", do: 0, else: opts[:order_type] || 0
    body = %{instrument_id: instrument_id, side: side, type: type, order_type: order_type}
    body = OkexService.optional_body(body, opts, [:client_oid, :price, :size, :notional])
    OkexService.request(service, :post, path, speed_limit, body: body)
  end

  @doc """
  撤单
  """
  def cancel_order(service, instrument_id, opts \\ []) do
    path = "/api/spot/v3/cancel_orders/#{OkexService.choose_one(opts, [:order_id, :client_oid])}"
    speed_limit = 2 / 100
    body = %{instrument_id: instrument_id}
    OkexService.request(service, :post, path, speed_limit, body: body)
  end

  @doc """
  获取订单信息
  """
  def get_order_info(service, instrument_id, opts \\ []) do
    path = "/api/spot/v3/orders/#{OkexService.choose_one(opts, [:order_id, :client_oid])}?instrument_id=#{instrument_id}"
    speed_limit = 2 / 20
    OkexService.request(service, :get, path, speed_limit)
  end

  @doc """
  委托策略下单
  """
  def submit_order_algo(service, instrument_id, order_type, side, size, opts \\ []) do
    path = "/api/spot/v3/order_algo"
    speed_limit = 2 / 40
    body = %{instrument_id: instrument_id, mode: "1", order_type: order_type, side: size, size: size}
    body = OkexService.optional_body(body, opts, [:trigger_price, :algo_price, :callback_rate, :algo_variance, :avg_amount, :limit_price, :sweep_range, :sweep_ratio, :single_limit, :limit_price, :time_interval])
    OkexService.request(service, :post, path, speed_limit, body: body)
  end

  @doc """
  委托策略撤单
  """
  def cancel_order_algo(service, instrument_id, order_type, algo_ids) do
    path = "/api/spot/v3/cancel_batch_algos"
    speed_limit = 2 / 20
    body = %{instrument_id: instrument_id, order_type: order_type, algo_ids: algo_ids}
    OkexService.request(service, :post, path, speed_limit, body: body)
  end

  @doc """
  获取委托单列表
  """
  def get_order_algo_list(service, instrument_id, order_type, opts \\ []) do
    optional_query = OkexService.optional_query(opts, [:status, :algo_id, :before, :after, :limit])
    path = "/api/spot/v3/algo?instrument_id=#{instrument_id}&order_type=#{order_type}#{if optional_query != "", do: "&#{optional_query}"}"
    speed_limit = 2 / 20
    OkexService.request(service, :get, path, speed_limit)
  end
end