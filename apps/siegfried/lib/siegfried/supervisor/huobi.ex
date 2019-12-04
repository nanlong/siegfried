defmodule Siegfried.HuobiSupervisor do
  use Supervisor

  alias Siegfried.Exchange
  alias TrendTracker.Helper, as: TrendTrackerHelper
  alias TrendTracker.Exchange.Helper, as: ExchangeHelper
  alias TrendTracker.Exchange.Huobi.WebSocket, as: HuobiWebSocket
  alias TrendTracker.Exchange.Producer
  alias TrendTracker.Exchange.Consumer

  @config Application.fetch_env!(:trend_tracker, :huobi)

  def start_link(_opts \\ []) do
    Supervisor.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    exchange = "huobi"

    children = Enum.map(@config[:contract_symbols], fn symbol ->
      producer = TrendTrackerHelper.system_name("producer", exchange: exchange, symbol: symbol)
      consumer = TrendTrackerHelper.system_name("consumer", exchange: exchange, symbol: symbol)
      websocket = TrendTrackerHelper.system_name("websocket", exchange: exchange, symbol: symbol)

      [
        Supervisor.child_spec({Producer, [name: producer]}, id: producer),
        Supervisor.child_spec({Consumer, [name: consumer, subscribe_to: [producer], on_message: fn
          %{"topic" => "kline"} = data ->
            attrs = Map.merge(data["data"], Map.take(data, ~w(exchange symbol period)))
            Exchange.create_kline(attrs)

          _ -> nil
        end]}, id: consumer),
        Supervisor.child_spec({HuobiWebSocket, [name: websocket, url: @config[:contract_ws], on_connect: fn pid ->
          trade_topic = "market.#{symbol}.trade.detail"
          kline_topics = ["market.#{symbol}.kline.1day", "market.#{symbol}.kline.1week"]

          HuobiWebSocket.on_message(pid, trade_topic, fn response ->
            trade = List.last(response["tick"]["data"])

            if trade do
              timestamp = TrendTrackerHelper.to_int(trade["ts"] / 1000)
              datetime = ExchangeHelper.timestamp_to_local(timestamp)
              data = %{"price" => trade["price"], "volume" => trade["amount"], "timestamp" => timestamp, "datetime" => datetime}
              item = %{"exchange" => exchange, "symbol" => symbol, "topic" => "trade", "data" => data}
              GenServer.call(producer, {:event, item})
            end
          end)

          Enum.each(kline_topics, fn kline_topic ->
            period = cond do
              String.ends_with?(kline_topic, "1day") -> "1day"
              String.ends_with?(kline_topic, "1week") -> "1week"
            end

            HuobiWebSocket.on_message(pid, kline_topic, fn response ->
              kline = response["tick"]

              if kline && is_map(kline) do
                timestamp = kline["id"]
                datetime = ExchangeHelper.timestamp_to_local(timestamp)
                data = Map.take(kline, ~w(open close low high))
                data = Map.merge(data, %{"timestamp" => timestamp, "datetime" => datetime})
                item = %{"exchange" => exchange, "symbol" => symbol, "topic" => "kline", "period" => period, "data" => data}
                GenServer.call(producer, {:event, item})
              end
            end)
          end)

          Enum.each([trade_topic] ++ kline_topics, fn topic ->
            Process.sleep(100)
            HuobiWebSocket.push(pid, %{sub: topic})
          end)
        end]}, id: websocket)
      ]
    end)
    |> List.flatten()

    children = if Application.get_env(:siegfried, :env) in [], do: children, else: []

    Supervisor.init(children, strategy: :one_for_one)
  end
end