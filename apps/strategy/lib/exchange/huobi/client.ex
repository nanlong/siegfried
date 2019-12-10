defmodule Strategy.Exchange.Huobi.Client do

  use GenServer

  alias Strategy.Exchange.Huobi.Service, as: HuobiService
  # alias Strategy.Exchange.Huobi.WebSocket, as: HuobiWebSocket

  @huobi Application.fetch_env!(:strategy, :huobi)

  def start_link(opts \\ []) do
    state = %{
      balance: opts[:balance],
      symbols: opts[:symbols],
      master: opts[:master],
      hedge: opts[:hedge],
      trade: opts[:trade],
    }
    GenServer.start_link(__MODULE__, state, opts)
  end

  def init(state) do
    # 分配资金
    symbols_balance = Map.new(state[:symbols], fn symbol -> {symbol, state[:balance] / length(state[:symbols])} end)

    # 初始化 rest api
    services = if state[:master] && state[:hedge] && state[:trade] do
      %{
        master_spot_service: HuobiService.start_link(@huobi[:spot_api], state[:master][:api_key]),
        master_contract_service: HuobiService.start_link(@huobi[:contract_api], state[:master][:api_key]),
        hedge_spot_service: HuobiService.start_link(@huobi[:spot_api], state[:hedge][:api_key]),
        hedge_contract_service: HuobiService.start_link(@huobi[:contract_api], state[:hedge][:api_key]),
        trade_spot_service: HuobiService.start_link(@huobi[:spot_api], state[:trade][:api_key]),
        trade_contract_service: HuobiService.start_link(@huobi[:contract_api], state[:trade][:api_key]),
      }
    end

    state = state |> Map.merge(%{symbols_balance: symbols_balance}) |> Map.merge(%{services: services})

    {:ok, state}
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
    symbols_balance = %{state[:symbols_balance] | symbol => balance}
    state = %{state | symbols_balance: symbols_balance}
    {:reply, state, state}
  end

  @doc """
  开仓
  """
  def open(_pid, _params, _opts \\ []) do

  end

  @doc """
  平仓
  """
  def close(_pid, _params, _opts \\ []) do

  end
end