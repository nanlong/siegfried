defmodule Strategy.TrendTracker.System do

  defmacro __using__(_opts) do
    quote do
      use Strategy.System

      alias Strategy.TrendTracker.Bankroll.Position

      @doc """
      信号
      """
      def handle_call({:signal, trade}, _from, state) do
        {:reply, {state[:symbol], signal(trade, state)}, state}
      end

      @doc """
      突破系统，突破价
      """
      def handle_call(:breakout, _from, state) do
        {:reply, {state[:symbol], breakout(state)}, state}
      end

      @doc """
      访问趋势系统，获取当前趋势
      """
      def get_trend(state) do
        if state[:systems][:trend] do
          {_symbol, trend} = GenServer.call(state[:systems][:trend], :trend)
          trend
        end
      end

      @doc """
      访问资金管理系统，获取当前仓位信息
      """
      def get_position(state) do
        if state[:systems][:bankroll] do
          {_symbol, position} = GenServer.call(state[:systems][:bankroll], :position)
          position
        end
      end

      @doc """
      信号
      """
      def signal(trade, state) do
        trend = get_trend(state)
        position = get_position(state)

        case breakout(state) do
          %{long_open: long_open, long_close: long_close, short_open: short_open, short_close: short_close} ->
            cond do
              not Position.empty?(position) && Position.long?(position) && trade["price"] <= long_close ->
                Logger.warn("平多止盈, #{trade["price"]} <= #{long_close}")
                {:close, position.trend, trade}

              not Position.empty?(position) && Position.short?(position) && trade["price"] >= short_close ->
                Logger.warn("平空止盈, #{trade["price"]} >= #{short_close}")
                {:close, position.trend, trade}

              Position.empty?(position) && trend == :long && trade["price"] >= long_open ->
                Logger.warn("开仓做多, #{trade["price"]} >= #{long_open}")
                {:open, trend, trade}

              Position.empty?(position) && trend == :short && trade["price"] <= short_open ->
                Logger.warn("开仓做空, #{trade["price"]} <= #{short_open}")
                {:open, trend, trade}

              true ->
                {:wait, trend, trade}
            end

          _ ->
            {:wait, trend, trade}
        end
      end

      def breakout(_state), do: raise("需要重写 `breakout/1` 函数")

      defoverridable signal: 2, breakout: 1
    end
  end
end