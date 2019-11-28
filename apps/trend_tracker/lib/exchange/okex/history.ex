defmodule TrendTracker.Exchange.Okex.History do
  @moduledoc """

  ## Examples

    iex> {:ok, pid} = OkexHistory.start_link("okex", "BTC-USD-SWAP", "1day")
    iex> OkexHistory.start(pid)

  """

  use GenServer

  alias TrendTracker.Exchange.Helper, as: ExchangeHelper
  alias TrendTracker.Exchange.Okex.Service, as: OkexService

  @okex Application.fetch_env!(:trend_tracker, :okex)

  def start_link(market, symbol, period, opts \\ []) do
    {:ok, service} = OkexService.start_link(@okex[:api])
    state = %{service: service, market: market, symbol: symbol, period: period}
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

    {path, keys} = case state[:market] do
      :spot -> {"/api/spot/v3/instruments/#{state[:symbol]}/candles", ["datetime", "open", "high", "low", "close", "volume"]}
      :swap -> {"/api/swap/v3/instruments/#{state[:symbol]}/candles", ["datetime", "open", "high", "low", "close", "volume", "currency_volume"]}
    end

    query = %{start: from, end: to, granularity: ExchangeHelper.seconds(state[:period])}

    case OkexService.get(state[:service], path, query: query) do
      {:ok, data} ->
        data = Enum.map(data, fn item ->
          kline = Map.new(Enum.zip(keys, item))
          Map.merge(kline, %{"timestamp" => d_t(kline["datetime"])})
        end)

        Enum.each(data, fn kline ->
          IO.puts("#{String.capitalize(to_string(state[:market]))} #{state[:symbol]} #{state[:period]} #{kline["datetime"]}")
          if is_function(state[:callback]), do: state[:callback].(kline)
        end)

        case List.last(Enum.slice(data, 1..-1)) do
          nil ->
            finished(pid)

          kline ->
            Process.sleep(100)
            start(pid, kline["timestamp"])
        end

      response ->
        IO.inspect "请求出错 #{inspect(response)}"
        finished(pid)
    end

    {:noreply, state}
  end

  def handle_info(:finished, state) do
    reason = "okex #{state[:market]} #{state[:symbol]} #{state[:period]} fetch klines history finished"
    Process.exit(self(), reason)
  end

  defp timerange(timestamp, state) do
    seconds = ExchangeHelper.seconds(state[:period])
    from = timestamp - 200 * seconds
    to = timestamp
    {t_d(from), t_d(to)}
  end

  defp d_t(d) do
    d
    |> NaiveDateTime.from_iso8601!()
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.to_unix()
  end

  defp t_d(t) do
    t
    |> DateTime.from_unix!()
    |> DateTime.to_iso8601()
  end
end