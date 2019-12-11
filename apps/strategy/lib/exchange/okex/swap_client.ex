defmodule Strategy.Exchange.Okex.SwapClient do
  @moduledoc """
  okex 客户端 - 交易永续合约

  ## Examples

    iex> {:ok, pid} = OkexSwapClient.start_link(balance: 10000, symbols: [], auth: ["passphrase", "access_key", "secret_key"])

  """
  use GenServer

  alias Strategy.Robot.DingDing
  alias Strategy.Exchange.Okex.Service, as: OkexService
  alias Strategy.Exchange.Okex.{AccountAPI, SpotAPI, SwapAPI}

  import Strategy.Helper
  import Strategy.Exchange.Helper

  @config Application.fetch_env!(:strategy, :okex)

  @fund_currency "usdt"

  def start_link(opts \\ []) do
    state = %{
      name: opts[:name],
      balance: opts[:balance],
      symbols: opts[:symbols],
      auth: opts[:auth],
      source: opts[:source],
    }
    GenServer.start_link(__MODULE__, state, opts)
  end

  def init(state) do
    # 交易账户
    {passphrase, access_key, secret_key} = state[:auth]
    {:ok, service} = OkexService.start_link(@config[:api], passphrase: passphrase, access_key: access_key, secret_key: secret_key)

    # 获取币币和永续合约的交易对信息
    {:ok, spot_instruments} = SpotAPI.get_instruments(service)
    {:ok, swap_instruments} = SwapAPI.get_instruments(service)

    symbols_instruments = Map.new(state[:symbols], fn swap_instrument_id ->
      swap_instrument = Enum.find(swap_instruments, fn item -> item["instrument_id"] == swap_instrument_id end)
      spot_instrument_id = String.upcase("#{swap_instrument["base_currency"]}-#{@fund_currency}")
      spot_instrument = Enum.find(spot_instruments, fn item -> item["instrument_id"] == spot_instrument_id end)
      {swap_instrument_id, %{"spot" => spot_instrument, "swap" => swap_instrument}}
    end)

    # 设定杠杆全仓模式50倍
    Enum.each(state[:symbols], fn instrument_id ->
      currency = symbols_instruments[instrument_id]["swap"]["base_currency"]
      {:ok, %{"margin_mode" => "crossed"}} = SwapAPI.set_leverage(service, currency, "50", "3")
    end)

    # 将资金转入币币账户
    {:ok, account} = AccountAPI.get_wallet(service, @fund_currency)

    if account && to_float(account["available"]) > 0 do
      {:ok, %{"result" => true}} = AccountAPI.transfer(service, @fund_currency, account["available"], 6, 1)
    end

    {:ok, spot_account} = SpotAPI.get_accounts(service, @fund_currency)

    if is_nil(spot_account) || to_float(spot_account["available"]) < state[:balance], do: raise("#{@fund_currency} 账户余额不足 #{state[:balance]}")

    default = Map.merge(state, %{
      symbols_instruments: symbols_instruments,
      symbols_balance: Map.new(state[:symbols], fn symbol -> {symbol, 0} end)
    })

    state = if state[:source] do
      case apply(state[:source], :get_cache, [state[:name], default]) do
        {:no_cache, state} ->
          message = """
          Okex 永续合约趋势跟踪系统启动

          跟踪币对：#{Enum.join(state[:symbols], "，")}
          可用额度：#{spot_account["available"]} USDT
          资金配额：#{state[:balance]} USDT
          """
          DingDing.send(message)
          state

        {:cached, state} -> state
      end
    else
      default
    end

    {:ok, Map.merge(state, %{service: service})}
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

    if state[:source] do
      key = to_string(state[:name])
      {:ok, _} = apply(state[:source], :set_cache, [key, state])
    end

    {:reply, state, state}
  end

  def handle_call({system, :open, trend, price, volume, opts}, _from, state) do
    spot_instrument = state[:symbols_instruments][opts[:symbol]]["spot"]
    swap_instrument = state[:symbols_instruments][opts[:symbol]]["swap"]
    currency = swap_instrument["base_currency"]

    state = if system == :breakout do
      # 开仓前准备
      notional = transfer_to_swap(state[:service], state[:balance], currency, price, to_float(spot_instrument["min_size"]))
      state = %{state | symbols_balance: %{state[:symbols_balance] | opts[:symbol] => notional}}

      if state[:source] do
        key = to_string(state[:name])
        {:ok, _} = apply(state[:source], :set_cache, [key, state])
      end

      state
    else
      state
    end

    {:ok, order} = SwapAPI.open_position(state[:service], currency, trend, to_string(volume))
    message = "#{opts[:symbol]} #{direction(system, :open, trend)}，价格：#{order["price_avg"]}，合约张数：#{order["filled_qty"]}"
    DingDing.send(message)
    file_log("okex.position.log", message)
    {:reply, %{"price" => to_float(order["price_avg"]), "volume" => to_int(order["filled_qty"]), "filled_cash_amount" => 0}, state}
  end

  def handle_call({system, :close, trend, price, volume, opts}, _from, state) do
    instrument = state[:symbols_instruments][opts[:symbol]]["swap"]
    currency = instrument["base_currency"]

    # 平仓
    {:ok, position_info} = SwapAPI.get_position(state[:service], currency: currency)
    Enum.each(position_info["holding"], fn position ->
      {:ok, _order} = SwapAPI.close_position(state[:service], currency, String.to_atom(position["side"]), position["avail_position"])
    end)

    # 转入到币币账户卖出
    {:ok, spot_account} = SpotAPI.get_accounts(state[:service], @fund_currency)
    {:ok, swap_account} = SwapAPI.get_accounts(state[:service], currency)
    {:ok, _} = AccountAPI.transfer(state[:service], currency, swap_account["info"]["max_withdraw"], 9, 1)
    {:ok, _} = SpotAPI.submit_market_order(state[:service], currency, "sell", size: swap_account["info"]["max_withdraw"])
    {:ok, spot_account_after} = SpotAPI.get_accounts(state[:service], @fund_currency)

    # 统计盈利情况
    filled_cash_amount = to_float(spot_account_after["available"]) - to_float(spot_account["available"])
    message = "#{opts[:symbol]} #{direction(system, :close, trend)}，预估价格：#{price}，合约张数：#{volume}。实际#{if filled_cash_amount > 0, do: "盈利", else: "亏损"}: #{filled_cash_amount} USDT"
    DingDing.send(message)
    file_log("okex.position.log", message)

    {:reply, %{"filled_cash_amount" => filled_cash_amount}, state}
  end

  def submit_order(client_name, {from, {action, trend, trade}}, volume, state) do
    GenServer.call(client_name, {from, action, trend, trade["price"], volume, state})
  end

  defp transfer_to_swap(service, balance, currency, price, min_size) do
    # 使用总资金5%
    notional = balance * 0.05

    # 购入现货
    if notional / price > min_size do
      {:ok, _order} = SpotAPI.submit_market_order(service, currency, "buy", notional: to_string(notional))
    else
      message = "错误：尝试币币交易，当前分配资金 #{balance}，5% 的资金可允许买入量不足 #{min_size} #{currency}"
      DingDing.send(message)
      raise(message)
    end

    # 转入到永续合约账户
    {:ok, account} = SpotAPI.get_accounts(service, currency)
    if to_float(account["available"]) > 0 do
      {:ok, _} = AccountAPI.transfer(service, currency, account["available"], 1, 9)
    end

    # 对冲
    hedge_size = to_int(notional / contract_size(currency))
    if hedge_size > 0 do
      {:ok, _} = SwapAPI.open_position(service, currency, :short, to_string(hedge_size))
    end

    notional
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
end