defmodule TrendTracker.System do

  defmacro __using__(_opts) do
    quote do
      use GenServer

      alias TrendTracker.Helper

      require Logger

      def start_link(opts \\ []) do
        state = %{
          exchange: opts[:exchange],
          symbol: opts[:symbol],
          period: opts[:period],
          klines: opts[:klines],
          systems: opts[:systems],
          indicators: opts[:indicators],
        }
        GenServer.start_link(__MODULE__, state, opts)
      end

      def init(state) do
        state = init_before(state)
        klines = generate_klines(state[:klines], state)
        state = %{state | klines: klines}
        state = init_after(state)
        {:ok, state}
      end

      @doc """
      压入K线，系统更新
      """
      def handle_cast({:kline, data}, state) do
        state = kline_before(state)
        klines = if List.last(state[:klines])["id"] == data["id"], do: Enum.slice(state[:klines], 0..-2), else: state[:klines]

        kline = state
        |> indicators()
        |> Enum.reduce(data, fn arg, data ->
          {arg, opts} = parse_indicator(arg)
          Helper.indicator(data, klines, arg, opts)
        end)

        state = %{state | klines: klines ++ [kline]}
        state = kline_after(state)

        {:noreply, state}
      end

      @doc """
      ping pong
      """
      def handle_call(:ping, _from, state) do
        {:reply, :pong, state}
      end

      @doc """
      K线级别
      """
      def handle_call(:period, _from, state) do
        {:reply, state[:period], state}
      end

      @doc """
      最近2个K线数据
      """
      def handle_call(:klines, _from, state) do
        {:reply, klines(state), state}
      end

      @doc """
      信号
      """
      def handle_call({:signal, trade}, _from, state) do
        {:reply, signal(trade, state), state}
      end

      @doc """
      获取K线指标的参数
      """
      def get_params(state, key) do
        state[:indicators][key] || default()[key]
      end

      @doc """
      使用K线指标初始化K线数据
      """
      def generate_klines(klines, state) do
        state
        |> indicators()
        |> Enum.reduce(klines, fn arg, acc ->
          {arg, opts} = parse_indicator(arg)

          acc
          |> Enum.with_index()
          |> Enum.reduce([], fn {kline, index}, acc ->
            acc ++ [Helper.indicator(kline, Enum.slice(acc, 0, index), arg, opts)]
          end)
        end)
      end

      @doc """
      解析K线指标参数
      """
      def parse_indicator(arg) do
        cond do
          is_tuple(arg) ->
            {arg, []}

          is_list(arg) ->
            {List.first(arg), Enum.slice(arg, 1..-1)}

          true ->
            message = "突破系统K线参数设置有误: #{inspect(arg)}"
            Logger.error(message)
            raise(message)
        end
      end

      @doc """
      访问趋势系统，获取当前趋势
      """
      def get_trend(state) do
        if state[:system][:trend] do
          GenServer.call(state[:system][:trend], :trend)
        end
      end

      @doc """
      访问资金管理系统，获取当前仓位信息
      """
      def get_position(state) do
        if state[:system][:bankroll] do
          GenServer.call(state[:system][:bankroll], :position)
        end
      end

      # init 初始化勾子回调
      def init_before(state), do: state
      def init_after(state), do: state

      # kline 更新勾子回调
      def kline_before(state), do: state
      def kline_after(state), do: state

      @doc """
      最近2条K线信息
      """
      def klines(state), do: Enum.slice(state[:klines], -2, 2)

      @doc """
      K线指标参数的默认值
      """
      def default, do: raise("需要重写 `default/0` 函数")

      @doc """
      K线指标
      """
      def indicators(_state), do: raise("需要重写 `indicators/1` 函数")

      @doc """
      信号
      """
      def signal(_trade, _state), do: raise("需要重写 `signal/2` 函数")

      defoverridable default: 0, indicators: 1, klines: 1, signal: 2, init_before: 1, init_after: 1, kline_before: 1, kline_after: 1
    end
  end
end