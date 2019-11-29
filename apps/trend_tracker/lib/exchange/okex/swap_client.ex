defmodule TrendTracker.Exchange.Okex.SwapClient do
  @moduledoc """
  okex 客户端 - 交易永续合约

  OkexSwapClient.test()

  """
  use GenServer

  alias TrendTracker.Exchange.Okex.Service, as: OkexService
  alias TrendTracker.Exchange.Okex.AccountAPI
  alias TrendTracker.Exchange.Okex.SwapAPI

  @config Application.fetch_env!(:trend_tracker, :okex)

  def start_link(opts \\ []) do
    state = %{
      balance: opts[:balance],
      symbols: opts[:symbols],
      passphrase: Enum.at(opts[:auth], 0),
      access_key: Enum.at(opts[:auth], 1),
      secret_key: Enum.at(opts[:auth], 2),
    }
    GenServer.start_link(__MODULE__, state, opts)
  end

  def init(state) do
    {:ok, service} = OkexService.start_link(
      @config[:api],
      passphrase: state[:passphrase],
      access_key: state[:access_key],
      secret_key: state[:secret_key]
    )
    {:ok, Map.merge(state, %{service: service})}
  end

  # def handle_call(_, _from, state) do

  # end

  # def submit_order(client_name, {from, {:open, trend, trade}}, volume, state) do
  #   symbol = state[:symbol]


  # end

  # def submit_order(client_name, {from, {:close, trend, trade}}, volume, state) do

  # end
end