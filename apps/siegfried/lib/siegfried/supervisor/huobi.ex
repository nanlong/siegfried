defmodule Siegfried.HuobiSupervisor do
  use Supervisor

  alias Siegfried.Exchange
  alias TrendTracker.Helper, as: TrendTrackerHelper
  alias TrendTracker.Exchange.Huobi.Helper, as: HuobiHelper
  alias TrendTracker.Exchange.Huobi.WebSocket, as: HuobiWebSocket
  alias TrendTracker.Exchange.Producer
  alias TrendTracker.Exchange.Consumer

  @config Application.fetch_env!(:trend_tracker, :huobi)

  def start_link(_opts) do
    Supervisor.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    children = Enum.map(@config[:contract_symbols], fn symbol ->
      producer = TrendTrackerHelper.system_name("producer", exchange: "huobi", symbol: symbol)
      consumer = TrendTrackerHelper.system_name("consumer", exchange: "huobi", symbol: symbol)
      websocket = TrendTrackerHelper.system_name("websocket", exchange: "huobi", symbol: symbol)

      [
        Supervisor.child_spec({Producer, [name: producer]}, id: producer),
        Supervisor.child_spec({Consumer, [name: consumer, subscribe_to: [producer], on_message: fn message ->
          topic = HuobiHelper.topic(message)
          data = message["tick"]

          case String.split(topic, ".") do
            ["market", symbol, "kline", period] when is_map(data) ->
              attrs = Exchange.kline_from_huobi(symbol, period, data)
              Exchange.create_kline(attrs)

            _ -> nil
          end
        end]}, id: consumer),
        Supervisor.child_spec({HuobiWebSocket, [name: websocket, url: @config[:contract_ws], on_connect: fn pid ->
          topics = ["market.#{symbol}.kline.1min", "market.#{symbol}.kline.1day", "market.#{symbol}.kline.1week", "market.#{symbol}.trade.detail"]

          Enum.each(topics, fn topic ->
            Process.sleep(100)
            HuobiWebSocket.push(pid, %{sub: topic})
            HuobiWebSocket.on_message(pid, topic, fn message -> GenServer.call(producer, {:event, message}) end)
          end)
        end]}, id: websocket)
      ]
    end)
    |> List.flatten()

    Supervisor.init(children, strategy: :one_for_one)
  end
end