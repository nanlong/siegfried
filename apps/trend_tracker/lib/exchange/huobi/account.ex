defmodule TrendTracker.Exchange.Huobi.Account do

  use GenServer

  alias TrendTracker.Exchange.Huobi.Service, as: HuobiService
  alias TrendTracker.Exchange.Huobi.WebSocket, as: HuobiWebSocket

  @huobi Application.fetch_env!(:trend_tracker, :huobi)

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
    services = if state[:master] && state[:hedge] && state[:trade] do
      %{
        master_spot_service: HuobiService.start_link(@huobi[:spot_api], state[:master][:api_key]),
        master_contract_service: HuobiService.start_link(@huobi[:contract_api], state[:master][:api_key]),
        hedge_spot_service: HuobiService.start_link(@huobi[:spot_api], state[:hedge][:api_key]),
        hedge_contract_service: HuobiService.start_link(@huobi[:contract_api], state[:hedge][:api_key]),
        trade_spot_service: HuobiService.start_link(@huobi[:spot_api], state[:trade][:api_key]),
        trade_contract_service: HuobiService.start_link(@huobi[:contract_api], state[:trade][:api_key]),
      }
    else
      %{}
    end

    {:ok, Map.merge(state, services)}
  end

  def handle_call(:balance, _from, state) do
    {:reply, state[:balance], state}
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