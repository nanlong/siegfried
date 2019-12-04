defmodule TrendTracker.Exchange.Okex.SwapAPI do
  alias TrendTracker.Exchange.Okex.Service, as: OkexService

  import TrendTracker.Helper
  import TrendTracker.Exchange.Helper

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
  def get_price_limit(service, currency) do
    path = "/api/swap/v3/instruments/#{currency}-usd-swap/price_limit"
    speed_limit = 2 / 20
    OkexService.request(service, :get, path, speed_limit)
  end

  @doc """
  获取合约标记价格
  """
  def get_mark_price(service, currency) do
    path = "/api/swap/v3/instruments/#{currency}-usd-swap/mark_price"
    speed_limit = 2 / 20
    OkexService.request(service, :get, path, speed_limit)
  end

  def get_depth(service, currency, opts \\ []) do
    path = "/api/swap/v3/instruments/#{currency}-usd-swap/depth?size=#{opts[:size] || 1}"
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
  def get_accounts(service, currency) do
    path = "/api/swap/v3/#{currency}-usd-swap/accounts"
    speed_limit = 2 / 20
    OkexService.request(service, :get, path, speed_limit)
  end

  @doc """
  所有合约持仓信息
  """
  def get_position(service, opts \\ []) do
    path = if opts[:currency], do: "/api/swap/v3/#{opts[:currency]}-usd-swap/position", else: "/api/swap/v3/position"
    speed_limit = if opts[:currency], do: 2 / 20, else: 10
    {:ok, data} = OkexService.request(service, :get, path, speed_limit)
    data = if opts[:side] in ["long", "short"], do: Enum.find(data["holding"], &(&1["side"] == opts[:side])), else: data
    {:ok, data}
  end

  @doc """
  获取某个合约的用户配置
  """
  def get_settings(service, currency) do
    path = "/api/swap/v3/accounts/#{currency}-usd-swap/settings"
    speed_limit = 2 / 5
    OkexService.request(service, :get, path, speed_limit)
  end

  @doc """
  设定某个合约的杠杆
  """
  def set_leverage(service, currency, leverage, side) do
    path = "/api/swap/v3/accounts/#{currency}-usd-swap/leverage"
    speed_limit = 2 / 5
    body = %{leverage: leverage, side: side}
    OkexService.request(service, :post, path, speed_limit, body: body)
  end

  @doc """
  开仓
  """
  def open_position(service, currency, trend, size) do
    type = if trend == :long, do: "1", else: "2"
    submit_market_order(service, currency, type, size)
  end

  @doc """
  平仓
  """
  def close_position(service, currency, trend, size) do
    type = if trend == :long, do: "3", else: "4"
    submit_market_order(service, currency, type, size)
  end

  @doc """
  下单
  """
  def submit_order(service, currency, type, price, size, opts \\ []) do
    path = "/api/swap/v3/order"
    speed_limit = 2 / 40
    body = %{instrument_id: "#{currency}-usd-swap", type: type, price: price, size: size}
    body = OkexService.optional_body(body, opts, [:client_oid, :order_type, :match_price])
    {:ok, data} = OkexService.request(service, :post, path, speed_limit, body: body)
    if data["error_code"] == "0", do: {:ok, data}, else: {:error, data}
  end

  @doc """
  模拟市价单
  """
  def submit_market_order(service, currency, type, size) do
    do_submit_market_order(service, currency, type, size, [])
  end

  defp do_submit_market_order(_service, currency, type, "0", result) do
    contract_size = contract_size(currency)
    filled_qty = result |> Enum.map(fn order -> to_int(order["filled_qty"]) end) |> Enum.sum()
    price_avg = contract_size * filled_qty / (result |> Enum.map(fn order -> contract_size * to_int(order["filled_qty"]) / to_float(order["price_avg"]) end) |> Enum.sum())
    {:ok, %{"instrument_id" => String.upcase("#{currency}-usd-swap"), "type" => type, "state" => "2", "filled_qty" => filled_qty, "price_avg" => price_avg}}
  end
  defp do_submit_market_order(service, currency, type, size, result) do
    case submit_order(service, currency, type, nil, size, match_price: "1") do
      {:error, %{"error_code" => "35014"}} ->
        do_submit_market_order(service, currency, type, size, result)

      {:ok, %{"order_id" => order_id}} ->
        {:ok, order} = wait_order_filled(service, currency, order_id: order_id)
        size = size |> Decimal.sub(order["filled_qty"]) |> Decimal.to_string()
        do_submit_market_order(service, currency, type, size, [order] ++ result)
    end
  end

  @doc """
  撤单
  """
  def cancel_order(service, currency, opts \\ []) do
    path = "/api/swap/v3/cancel_order/#{currency}-usd-swap/#{OkexService.choose_one(opts, [:order_id, :client_oid])}"
    speed_limit = 2 / 40
    OkexService.request(service, :post, path, speed_limit)
  end

  def get_orders(service, currency, opts \\ []) do
    optional_query = OkexService.optional_query(opts, [:before, :after, :limit])
    path = "/api/swap/v3/orders/#{currency}-usd-swap?state=#{opts[:state] || 2}#{if optional_query != "", do: "&#{optional_query}"}"
    speed_limit = 2 / 20
    OkexService.request(service, :get, path, speed_limit)
  end

  @doc """
  获取订单信息
  """
  def get_order_info(service, currency, opts \\ []) do
    path = "/api/swap/v3/orders/#{currency}-usd-swap/#{OkexService.choose_one(opts, [:order_id, :client_oid])}"
    speed_limit = 2 / 40
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
  def submit_order_algo(service, currency, order_type, type, size, opts \\ []) do
    path = "/api/swap/v3/order_algo"
    speed_limit = 2 / 40
    body = %{instrument_id: "#{currency}-usd-swap", order_type: order_type, type: type, size: size}
    optional_keys = [:trigger_price, :algo_price, :callback_rate, :algo_variance, :avg_amount,
                    :limit_price, :sweep_range, :sweep_ratio, :single_limit, :limit_price, :time_interval]
    body = OkexService.optional_body(body, opts, optional_keys)
    OkexService.request(service, :post, path, speed_limit, body: body)
  end

  @doc """
  委托策略撤单
  """
  def cancel_order_algo(service, currency, order_type, algo_ids) do
    path = "/api/swap/v3/cancel_algos"
    speed_limit = 2 / 20
    body = %{instrument_id: "#{currency}-usd-swap", order_type: order_type, algo_ids: algo_ids}
    OkexService.request(service, :post, path, speed_limit, body: body)
  end

  @doc """
  获取委托单列表
  """
  def get_order_algo_list(service, currency, order_type, opts \\ []) do
    optional_query = OkexService.optional_query(opts, [:status, :algo_id, :before, :after, :limit])
    path = "/api/swap/v3/order_algo/#{currency}-usd-swap?order_type=#{order_type}#{if optional_query != "", do: "&#{optional_query}"}"
    speed_limit = 2 / 20
    OkexService.request(service, :get, path, speed_limit)
  end
end