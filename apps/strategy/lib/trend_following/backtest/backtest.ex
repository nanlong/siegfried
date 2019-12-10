defmodule Strategy.TrendFollowing.Backtest do
  @moduledoc """

  opts = [
    title: "test",
    balance: 1500,
    exchange: "huobi",
    symbols: ["btcusdt", "ethusdt", "eosusdt", "bchusdt"],
    trend: [module: "Macd", period: "1week"],
    breakout: [module: "BollingerBands", period: "1day"],
    bankroll: [period: "1day"],
    trader: [],
    source: Siegfried,
  ]

  Strategy.TrendFollowing.Backtest.start(opts)
  """

  alias Strategy.Helper
  alias Strategy.TrendFollowing.Worker
  alias Strategy.Exchange.Producer

  require Logger

  def start(opts) do
    symbols_klines = Map.new(opts[:symbols], fn symbol ->
      klines = Map.new([:trend, :breakout, :bankroll], fn system ->
        # 2018-10-01 1538323200
        {system, opts[:source].list_klines(opts[:exchange], symbol, opts[system][:period], 0, 1538323200)}
      end)
      {symbol, klines}
    end)

    opts = opts ++ [backtest: true, symbols_klines: symbols_klines]

    producers = Map.new(opts[:symbols], fn symbol ->
      opts = Keyword.take(opts, [:exchange, :backtest]) ++ [symbol: symbol]
      producer_name = Helper.system_name("producer", opts)
      {:ok, _} = Producer.start_link(name: producer_name)
      {symbol, producer_name}
    end)

    {:ok, worker_pid} = Worker.start_link()
    :ok = Worker.start(worker_pid, Keyword.delete(opts, :source))

    task = fn symbol -> Task.async(fn ->
      klines = opts[:symbols_klines][symbol][:breakout]
      kline = if klines && length(klines) > 0, do: List.last(klines), else: opts[:source].first_kline(opts[:exchange], symbol, "1day")
      push_data(worker_pid, producers[symbol], opts[:source], opts[:exchange], symbol, kline["timestamp"], [])
    end) end

    Enum.each(opts[:symbols], fn symbol -> task.(symbol) end)
  end

  defp push_data(worker, producer, source, exchange, symbol, from, cache) do
    start_time = :os.system_time(:microsecond)
    klines_1min = source.list_klines(exchange, symbol, "1min", from, from + 86400)
    data = Enum.slice(klines_1min, 0..-2)
    cache = cache ++ data
    first_kline_1min = List.first(klines_1min)
    last_kline_1min = List.last(klines_1min)
    datetime = String.slice(first_kline_1min["datetime"], 0..9)

    if first_kline_1min do
      Logger.info("#{symbol} 数据时间：#{datetime}")
    end

    Enum.each(data, fn kline_1min ->
      kline_1day = source.get_kline(exchange, symbol, "1day", kline_1min, cache)
      kline_1week = source.get_kline(exchange, symbol, "1week", kline_1min, cache)

      if kline_1day do
        kline = %{"exchange" => exchange, "symbol" => symbol, "topic" => "kline", "period" => "1day", "data" => kline_1day}
        GenServer.call(producer, {:event, kline})
      end

      if kline_1week do
        kline = %{"exchange" => exchange, "symbol" => symbol, "topic" => "kline", "period" => "1week", "data" => kline_1week}
        GenServer.call(producer, {:event, kline})
      end

      trade = %{"exchange" => exchange, "symbol" => symbol, "topic" => "trade", "data" => %{"datetime" => kline_1min["datetime"], "price" => kline_1min["close"]}}
      GenServer.call(producer, {:event, trade})
    end)

    Logger.info("#{symbol} #{datetime} 耗时：#{Float.round((:os.system_time(:microsecond) - start_time) / 1000 / 1000, 6)}秒")

    if length(klines_1min) > 1 do
      cache = if length(cache) > 10080, do: Enum.slice(cache, -10080, 10080), else: cache
      push_data(worker, producer, source, exchange, symbol, last_kline_1min["timestamp"], cache)
    else
      kline_1min = source.last_kline(exchange, symbol, "1min")
      data = %{"backtest" => "finished", "trade" => %{"datetime" => kline_1min["datetime"], "price" => kline_1min["close"]}}
      GenServer.call(producer, {:event, data})
    end
  end
end