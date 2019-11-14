defmodule TrendTracker.Trader do
  use GenStage

  alias TrendTracker.Helper

  def start_link(opts \\ []) do
    state = %{
      exchange: opts[:exchange],
      symbol: opts[:symbol],
      systems: opts[:systems],
    }
    GenStage.start_link(__MODULE__, state, opts)
  end

  def init(state) do
    state = Map.merge(state, %{
      trend_period: GenServer.call(state[:systems][:trend], :period),
      breakout_period: GenServer.call(state[:systems][:breakout], :period),
      bankroll_period: GenServer.call(state[:systems][:bankroll], :period)
    })

    opts = state |> Map.take([:exchange, :symbol]) |> Map.to_list()
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
                GenServer.cast(state[:symbols][system], {:kline, data})
              end
            end)

          ["market", symbol, "trade", "detail"] ->
            trade = List.last(data["data"])

            if symbol == state[:symbol] && trade do
              signal = system_signal(trade, state)
              submit_order(signal, state)
            end

          _ -> nil
        end

      _ -> nil
    end)

    {:noreply, [], state}
  end

  # 根据持仓状态，获取系统信号
  defp system_signal(trade, state) do
    position = GenServer.call(state[:symbols][:bankroll], :position)
    system = if position.status == :empty, do: state[:symbols][:breakout], else: state[:symbols][:bankroll]
    GenServer.call(system, {:signal, trade})
  end

  # 根据信号，开仓或者平仓
  defp submit_order({:wait, _, _}, _state), do: nil
  defp submit_order({_action, _trend, _trade}, _state) do

  end
end