defmodule TrendTracker.Exchange.Huobi.History do
  @moduledoc """
  获取火币K线历史数据

  ## Examples

    iex> {:ok, pid} = HuobiHistory.start_link(:spot, "btcusdt", "1day")
    iex> HuobiHistory.on_message(pid, fn msg -> IO.inspect(msg) end)
    iex> HuobiHistory.start(pid)

  """

  use GenServer

  alias TrendTracker.Exchange.Huobi.Helper, as: HuobiHelper
  alias TrendTracker.Exchange.Huobi.WebSocket, as: HuobiWebSocket

  require Logger

  @huobi Application.fetch_env!(:trend_tracker, :huobi)

  def start_link(market, symbol, period, opts \\ []) do
    ws = @huobi[String.to_atom("#{market}_ws")]
    {:ok, websocket} = HuobiWebSocket.start_link(url: ws, debug: [:trace])
    state = %{websocket: websocket, market: market, symbol: symbol, period: period, start: opts[:start]}
    GenServer.start_link(__MODULE__, state, opts)
  end

  def init(state) do
    if state[:start], do: start(self())
    {:ok, state}
  end

  def start(pid, timestamp \\ nil)
  def start(pid, nil), do: start(pid, :os.system_time(:second))
  def start(pid, timestamp) do
    Process.send_after(pid, {:fetch, timestamp}, 500)
    :ok
  end

  def finished(pid) do
    Process.send_after(pid, :finished, 0)
    :ok
  end

  def on_message(pid, callback) do
    GenServer.call(pid, {:on_message, callback})
  end

  def handle_call({:on_message, callback}, _from, state) do
    {:reply, :ok, Map.merge(state, %{callback: callback})}
  end

  def handle_info({:fetch, timestamp}, state) do
    pid = self()
    {from, to} = timerange(timestamp, state)
    message = %{req: "market.#{state[:symbol]}.kline.#{state[:period]}", from: from, to: to}

    HuobiWebSocket.push(state[:websocket], message, fn
      %{"status" => "ok", "data" => data} ->
        data
        |> Enum.reverse()
        |> Enum.each(fn kline ->
          IO.puts("#{String.capitalize(to_string(state[:market]))} #{state[:symbol]} #{state[:period]} #{DateTime.from_unix!(kline["id"], :second)}")
          if is_function(state[:callback]), do: state[:callback].(kline)
        end)

        case List.first(data) do
          nil -> finished(pid)
          kline -> start(pid, kline["id"])
        end

      response ->
        Logger.error("获取数据出错: #{inspect(response)}")
    end)

    {:noreply, state}
  end

  def handle_info(:finished, state) do
    reason = "huobi #{state[:market]} #{state[:symbol]} #{state[:period]} fetch klines history finished"
    Process.exit(self(), reason)
  end

  defp timerange(timestamp, state) do
    seconds = HuobiHelper.seconds(state[:period])
    count = if state[:market] == :contract, do: 2000, else: 300
    {timestamp - count * seconds, timestamp - seconds}
  end
end