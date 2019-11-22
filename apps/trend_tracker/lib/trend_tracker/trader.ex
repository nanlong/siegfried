defmodule TrendTracker.Trader do
  use GenStage

  alias TrendTracker.Helper
  alias TrendTracker.Exchange.Huobi.Client, as: HuobiClient
  alias TrendTracker.Backtest.Client, as: BacktestClient
  alias TrendTracker.Bankroll.Position

  require Logger

  def start_link(opts \\ []) do
    state = %{
      exchange: opts[:exchange],
      symbol: opts[:symbol],
      systems: opts[:systems],
      backtest: opts[:backtest],
    }
    GenStage.start_link(__MODULE__, state, opts)
  end

  def init(state) do
    symbol = state[:symbol]
    {^symbol, trend_period} = GenServer.call(state[:systems][:trend], :period)
    {^symbol, breakout_period} = GenServer.call(state[:systems][:breakout], :period)
    {^symbol, bankroll_period} = GenServer.call(state[:systems][:bankroll], :period)

    state = Map.merge(state, %{trend_period: trend_period, breakout_period: breakout_period, bankroll_period: bankroll_period})

    opts = state |> Map.take([:exchange, :symbol, :backtest]) |> Map.to_list()
    producer = Helper.system_name("producer", opts)

    {:consumer, state, subscribe_to: [producer]}
  end

  def handle_events(events, _from, state) do
    Enum.each(events, fn
      %{"ch" => topic, "tick" => data} ->
        case String.split(topic, ".") do
          ["market", symbol, "kline", period] ->
            systems = [
              {:trend, state[:trend_period]},
              {:breakout, state[:breakout_period]},
              {:bankroll, state[:bankroll_period]}
            ]

            Enum.each(systems, fn {system, system_period} ->
              if symbol == state[:symbol] && period == system_period do
                Logger.debug "Trader push kline: #{system} #{symbol} #{period}"
                GenServer.cast(state[:systems][system], {:kline, data})
              end
            end)

          ["market", symbol, "trade", "detail"] ->
            trade = List.last(data["data"])

            if symbol == state[:symbol] && trade do
              signal = system_signal(trade, state)
              Logger.debug "Trader signal: #{inspect(signal)}"
              submit_order(signal, state)
            end

          _ -> nil
        end

      %{"backtest" => "finished", "trade" => trade} ->
        if state[:backtest] do
          Logger.info("#{state[:symbol]} 回测完毕")
          symbol = state[:symbol]
          {^symbol, position} = GenServer.call(state[:systems][:bankroll], :position)

          if position.status != :empty do
            {:ok, order} = BacktestClient.submit_order(nil, :close, position.trend, trade["price"], Position.volume(position), trade["ts"], state)
            GenServer.call(state[:systems][:bankroll], :close)
            GenServer.call(state[:systems][:client], {:profit, state[:symbol], order["filled_cash_amount"]})
          end

          balance = GenServer.call(state[:systems][:client], :balance)
          Helper.file_log("#{trade["datetime"]} 资金总值：#{Helper.float_to_binary(balance, 8)}")
        end

      _ -> nil
    end)

    {:noreply, [], state}
  end

  # 根据持仓状态，获取系统信号
  defp system_signal(trade, state) do
    symbol = state[:symbol]
    {^symbol, position} = GenServer.call(state[:systems][:bankroll], :position)
    {^symbol, breakout_signal} = GenServer.call(state[:systems][:breakout], {:signal, trade})
    {^symbol, bankroll_signal} = GenServer.call(state[:systems][:bankroll], {:signal, trade})

    cond do
      # 止盈
      not Position.empty?(position) && elem(breakout_signal, 0) == :close -> breakout_signal
      # 止损
      not Position.empty?(position) && elem(bankroll_signal, 0) == :close -> bankroll_signal
      # 可能开仓
      Position.empty?(position) -> breakout_signal
      # 可能加仓
      true -> bankroll_signal
    end
  end

  # 根据信号，开仓或者平仓
  defp submit_order({:wait, _, _}, _state), do: nil
  defp submit_order({action, trend, trade}, %{backtest: true} = state) do
    client_name = state[:systems][:client]
    symbol = state[:symbol]
    {^symbol, position} = GenServer.call(state[:systems][:bankroll], :position)

    client = cond do
      state[:backtest] -> BacktestClient
      state[:exchange] == "huobi" -> HuobiClient
    end

    case action do
      :open ->
        {:ok, order} = client.submit_order(client_name, action, trend, position.open_price, position.volume, trade["ts"], state)
        GenServer.call(state[:systems][:bankroll], {:open, trend, order["price"], order["volume"]})

      :close ->
        {:ok, order} = client.submit_order(client_name, action, trend, position.close_price, Position.volume(position), trade["ts"], state)
        GenServer.call(state[:systems][:bankroll], :close)
        GenServer.call(state[:systems][:client], {:profit, state[:symbol], order["filled_cash_amount"]})
    end
  end
end