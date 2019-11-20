defmodule TrendTracker.Backtest do
  @moduledoc """

  opts = [
    title: "test",
    balance: 10000,
    exchange: "huobi",
    symbols: ["BTC_CQ"],
    trend: [module: "Macd", period: "1week"],
    breakout: [module: "BollingerBands", period: "1day"],
    turtle: [period: "1day"],
    trader: [],
    source: Siegfried,
  ]

  TrendTracker.Backtest.start(opts)
  """

  alias TrendTracker.Helper
  alias TrendTracker.Worker
  alias TrendTracker.Exchange.Producer

  require Logger

  def start(opts) do
    opts = opts ++ [backtest: true]

    producers = Map.new(opts[:symbols], fn symbol ->
      opts = Keyword.take(opts, [:exchange, :backtest]) ++ [symbol: symbol]
      producer_name = Helper.system_name("producer", opts)
      {:ok, _} = Producer.start_link(name: producer_name)
      {symbol, producer_name}
    end)

    {:ok, pid} = Worker.start_link()
    :ok = Worker.start(pid, Keyword.delete(opts, :source))

    Enum.each(opts[:symbols], fn symbol -> Task.async(fn ->
      kline = opts[:source].first_kline(opts[:exchange], symbol, "1day")
      push_data(pid, producers[symbol], opts[:source], opts[:exchange], symbol, kline["timestamp"])
    end) end)
  end

  defp push_data(worker, producer, source, exchange, symbol, from) do
    klines_1min = source.list_klines(exchange, symbol, "1min", from, from + 1440 * 60)
    last_kline_1min = List.last(klines_1min)

    Enum.each(klines_1min, fn kline_1min ->
      if String.contains?(kline_1min["datetime"], "00:00:00+08:00") do
        Logger.info("#{symbol} 数据时间：#{kline_1min["datetime"]}")
        # Logger.info("trend: #{inspect(Worker.trend(worker))}")
        # Logger.info("trend kline: #{inspect(Worker.kline(worker, :trend))}")
        # Logger.info("breakout kline: #{inspect(Worker.kline(worker, :breakout))}")
        # Logger.info("position: #{inspect(Worker.position(worker))}")
        # Logger.info("bankroll kline: #{inspect(Worker.kline(worker, :bankroll))}")
      end

      kline_1day = source.get_kline(exchange, symbol, "1day", kline_1min["timestamp"])
      kline_1week = source.get_kline(exchange, symbol, "1week", kline_1min["timestamp"])

      if kline_1day do
        GenServer.call(producer, {:event, %{"ch" => "market.#{symbol}.kline.1day", "tick" => kline_1day}})
      end

      if kline_1week do
        GenServer.call(producer, {:event, %{"ch" => "market.#{symbol}.kline.1week", "tick" => kline_1week}})
      end

      tick = %{"data" => [%{"ts" => kline_1min["timestamp"], "price" => kline_1min["close"]}]}
      GenServer.call(producer, {:event, %{"ch" => "market.#{symbol}.trade.detail", "tick" => tick}})
    end)

    if length(klines_1min) > 1 do
      push_data(worker, producer, source, exchange, symbol, last_kline_1min["timestamp"] + 60)
    else
      Logger.info("回测完毕")
    end
  end
end