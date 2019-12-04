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
  def submit_order(service, currency, type, side, opts \\ []) do
    path = "/api/spot/v3/orders"
    speed_limit = 2 / 100
    order_type = if type == "market", do: 0, else: opts[:order_type] || 0
    body = %{instrument_id: "#{currency}-usdt", side: side, type: type, order_type: order_type}
    body = OkexService.optional_body(body, opts, [:client_oid, :price, :size, :notional])
    OkexService.request(service, :post, path, speed_limit, body: body)
  end

  def submit_market_order(service, currency, side, opts \\ []) do
    {:ok, %{"result" => true, "order_id" => order_id}} = submit_order(service, currency, "market", side, opts)
    wait_order_filled(service, currency, order_id: order_id)
  end

  @doc """
  撤单
  """
  def cancel_order(service, currency, opts \\ []) do
    path = "/api/spot/v3/cancel_orders/#{OkexService.choose_one(opts, [:order_id, :client_oid])}"
    speed_limit = 2 / 100
    body = %{instrument_id: "#{currency}-usdt"}
    OkexService.request(service, :post, path, speed_limit, body: body)
  end

  @doc """
  获取订单信息
  """
  def get_order_info(service, currency, opts \\ []) do
    path = "/api/spot/v3/orders/#{OkexService.choose_one(opts, [:order_id, :client_oid])}?instrument_id=#{currency}-usdt"
    speed_limit = 2 / 20
    OkexService.request(service, :get, path, speed_limit)
  end

  @doc """
  等待订单成交
  """
  def wait_order_filled(service, currency, opts \\ []) do
    Enum.reduce_while(1..60, {:error, nil}, fn _x, _acc ->
      {:ok, order_info} = get_order_info(service, currency, opts)

      if order_info["state"] == "2" do
        {:halt, {:ok, order_info}}
      else
        Process.sleep(1000)
        {:cont, {:error, order_info}}
      end
    end)
  end

  @doc """
  委托策略下单
  """
  def submit_order_algo(service, currency, order_type, side, size, opts \\ []) do
    path = "/api/spot/v3/order_algo"
    speed_limit = 2 / 40
    body = %{instrument_id: "#{currency}-usdt", mode: "1", order_type: order_type, side: side, size: size}
    optional_keys = [:trigger_price, :algo_price, :callback_rate, :algo_variance, :avg_amount,
                    :limit_price, :sweep_range, :sweep_ratio, :single_limit, :limit_price, :time_interval]
    body = OkexService.optional_body(body, opts, optional_keys)
    OkexService.request(service, :post, path, speed_limit, body: body)
  end

  @doc """
  委托策略撤单
  """
  def cancel_order_algo(service, currency, order_type, algo_ids) do
    path = "/api/spot/v3/cancel_batch_algos"
    speed_limit = 2 / 20
    body = %{instrument_id: "#{currency}-usdt", order_type: order_type, algo_ids: algo_ids}
    OkexService.request(service, :post, path, speed_limit, body: body)
  end

  @doc """
  获取委托单列表
  """
  def get_order_algo_list(service, currency, order_type, opts \\ []) do
    optional_query = OkexService.optional_query(opts, [:status, :algo_id, :before, :after, :limit])
    path = "/api/spot/v3/algo?instrument_id=#{currency}-usdt&order_type=#{order_type}#{if optional_query != "", do: "&#{optional_query}"}"
    speed_limit = 2 / 20
    OkexService.request(service, :get, path, speed_limit)
  end
end