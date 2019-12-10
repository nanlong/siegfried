defmodule Siegfried.OkexSupervisor do
  use Supervisor

  alias Siegfried.Exchange
  alias Strategy.Exchange.Helper, as: ExchangeHelper
  alias Strategy.Exchange.Okex.WebSocket, as: OkexWebSocket
  alias Strategy.Exchange.Producer
  alias Strategy.Exchange.Consumer

  import Strategy.Helper

  @config Application.fetch_env!(:strategy, :okex)

  def start_link(_opts \\ []) do
    Supervisor.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    exchange = "okex"

    children = Enum.map(@config[:contract_symbols], fn symbol ->
      producer = system_name("producer", exchange: exchange, symbol: symbol)
      consumer = system_name("consumer", exchange: exchange, symbol: symbol)
      websocket = system_name("websocket", exchange: exchange, symbol: symbol)

      [
        Supervisor.child_spec({Producer, [name: producer]}, id: producer),
        Supervisor.child_spec({Consumer, [name: consumer, subscribe_to: [producer], on_message: fn
          %{"topic" => "kline"} = data ->
            attrs = Map.merge(data["data"], Map.take(data, ~w(exchange symbol period)))
            Exchange.create_kline(attrs)

          _ -> nil
        end]}, id: consumer),
        Supervisor.child_spec({OkexWebSocket, [name: websocket, url: @config[:ws], on_connect: fn pid ->
          trade_topic = "swap/trade:#{symbol}"
          kline_topics = ["swap/candle86400s:#{symbol}", "swap/candle604800s:#{symbol}"]

          Process.sleep(100)

          OkexWebSocket.on_message(pid, trade_topic, fn response ->
            trade = List.last(response["data"])

            if trade do
              price = to_float(trade["price"])
              volume = to_int(trade["size"])
              timestamp = ExchangeHelper.datetime_to_timestamp(trade["timestamp"])
              datetime = ExchangeHelper.timestamp_to_local(timestamp)
              data = %{"price" => price, "volume" => volume, "timestamp" => timestamp, "datetime" => datetime}
              item = %{"exchange" => exchange, "symbol" => symbol, "topic" => "trade", "data" => data}
              GenServer.call(producer, {:event, item})
            end
          end)

          Enum.each(kline_topics, fn kline_topic ->
            period = cond do
              String.starts_with?(kline_topic, "swap/candle86400s") -> "1day"
              String.starts_with?(kline_topic, "swap/candle604800s") -> "1week"
            end

            OkexWebSocket.on_message(pid, kline_topic, fn response ->
              keys = ~w(datetime open high low close volume currency_volume)

              Enum.each(response["data"], fn kline ->
                data = Map.new(Enum.zip(keys, kline["candle"]))
                timestamp = ExchangeHelper.datetime_to_timestamp(data["datetime"])
                datetime = ExchangeHelper.timestamp_to_local(timestamp)
                data = Map.merge(data, %{"timestamp" => timestamp, "datetime" => datetime})
                data = Enum.reduce(["open", "close", "high", "low"], data, fn key, acc -> Map.update!(acc, key, &to_float/1) end)
                item = %{"exchange" => exchange, "symbol" => symbol, "topic" => "kline", "period" => period, "data" => data}
                GenServer.call(producer, {:event, item})
              end)
            end)
          end)

          OkexWebSocket.push(pid, %{op: "subscribe", args: [trade_topic] ++ kline_topics})
        end]}, id: websocket)
      ]
    end)
    |> List.flatten()

    children = if Application.get_env(:siegfried, :env) in [:staging, :prod], do: children, else: []

    Supervisor.init(children, strategy: :one_for_one)
  end
end