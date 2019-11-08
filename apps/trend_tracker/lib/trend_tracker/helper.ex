defmodule TrendTracker.Helper do

  @doc """
  真实波动幅度

  ## Parameters

    - high: 当日最高价
    - low: 当日最低价
    - pre_close: 前一日收盘价

  ## Examples

    iex> TrendTracker.Helper.true_range(20, 15, 17)
    5

  """
  def true_range(high, low, pre_close) do
    (high - low) |> max(high - pre_close) |> max(pre_close - low)
  end

  @doc """
  真实波动幅度均值

  ## Parameters

    - tr: 当日真实波幅
    - pre_atr: 前一日真实波幅均值
    - opts:
      - period: 可设置周期，默认`20`

  ## Examples

    iex> TrendTracker.Helper.average_true_range(10, 9)
    9.05

  """
  def average_true_range(tr, pre_atr, period \\ 20) do
    ((period - 1) * pre_atr + tr) / period
  end

  @doc """
  K线指标

    - kline: 当天K线
    - history: 历史K线
    - kline_index: 指标
    - opts:
      - rename: 重设指标名称

  """
  def indicator(kline, history, kline_index, opts \\ [])

  @doc """
  真实波幅
  """
  def indicator(kline, history, :tr, _opts) do
    pre_kline = List.last(history)
    pre_close = if pre_kline, do: pre_kline["close"], else: kline["close"]
    Map.put(kline, "tr", true_range(kline["high"], kline["low"], pre_close))
  end

  @doc """
  平均真实波幅
  """
  def indicator(kline, history, {:atr, period}, _opts) when length(history) < period - 1 do
    kline
  end
  def indicator(kline, history, {:atr, period}, opts) when length(history) == period - 1 do
    key = if opts[:rename], do: opts[:rename], else: "atr_#{period}"
    indicator(kline, history, {:ma, "tr", period}, rename: key)
  end
  def indicator(kline, history, {:atr, period}, opts) do
    key = if opts[:rename], do: opts[:rename], else: "atr_#{period}"
    pre_kline = List.last(history)

    if Map.has_key?(pre_kline, key) do
      value = average_true_range(kline["tr"], pre_kline[key], period)
      Map.put(kline, key, value)
    else
      kline
    end
  end

  @doc """
  周期内最高
  """
  def indicator(kline, history, {:max, _source, period}, _opts) when length(history) < period - 1 do
    kline
  end
  def indicator(kline, history, {:max, source, period}, opts) do
    key = if opts[:rename], do: opts[:rename], else: "max_#{source}_#{period}"
    klines = Enum.slice(history ++ [kline], -period, period)

    if all_has_key?(klines, source) do
      value = klines |> Enum.map(&(&1[source])) |> Enum.max()
      Map.put(kline, key, value)
    else
      kline
    end
  end

  @doc """
  周期内最低
  """
  def indicator(kline, history, {:min, _source, period}, _opts) when length(history) < period - 1 do
    kline
  end
  def indicator(kline, history, {:min, source, period}, opts) do
    key = if opts[:rename], do: opts[:rename], else: "min_#{source}_#{period}"
    klines = Enum.slice(history ++ [kline], -period, period)

    if all_has_key?(klines, source) do
      value = klines |> Enum.map(&(&1[source])) |> Enum.min()
      Map.put(kline, key, value)
    else
      kline
    end
  end

  @doc """
  移动均线
  """
  def indicator(kline, history, {:ma, _source, period}, _opts) when length(history) < period - 1 do
    kline
  end
  def indicator(kline, history, {:ma, source, period}, opts) do
    key = if opts[:rename], do: opts[:rename], else: "ma_#{source}_#{period}"
    klines = Enum.slice(history ++ [kline], -period, period)

    if all_has_key?(klines, source) do
      value = klines |> Enum.map(&(&1[source])) |> Enum.sum() |> Kernel./(period)
      Map.put(kline, key, value)
    else
      kline
    end
  end

  @doc """
  指数移动均线
  """
  def indicator(kline, history, {:ema, _source, period}, _opts) when length(history) < period - 1 do
    kline
  end
  def indicator(kline, history, {:ema, source, period}, opts) do
    key = if opts[:rename], do: opts[:rename], else: "ema_#{source}_#{period}"
    pre_kline = List.last(history)

    if Map.has_key?(pre_kline, key) do
      value = pre_kline[key] * (period - 1) / (period + 1) + kline[source] * 2 / (period + 1)
      Map.put(kline, key, value)
    else
      indicator(kline, history, {:ma, source, period}, rename: key)
    end
  end

  @doc """
  平均差值
  """
  def indicator(kline, history, {:md, _source, period}, _opts) when length(history) < period - 1 do
    kline
  end
  def indicator(kline, history, {:md, source, period}, opts) do
    if Map.has_key?(kline, source) do
      key = if opts[:rename], do: opts[:rename], else: "md_#{period}"

      value = (history ++ [kline])
      |> Enum.slice(-period, period)
      |> Enum.map(&(&1["close"]))
      |> Enum.map(&((&1 - kline[source]) |> abs() |> :math.pow(2)))
      |> Enum.sum()
      |> Kernel./(period)
      |> :math.sqrt()

      Map.put(kline, key, value)
    else
      kline
    end
  end

  @doc """
  MACD Line 差离值
  """
  def indicator(kline, _history, {:dif, source_x, source_y}, _opts) do
    if Map.has_key?(kline, source_x) && Map.has_key?(kline, source_y) do
      Map.put(kline, "dif", kline[source_x] - kline[source_y])
    else
      kline
    end
  end

  @doc """
  MACD Histogram 柱状图
  """
  def indicator(kline, _history, {:hist, power}, _opts) do
    if Map.has_key?(kline, "dif") && Map.has_key?(kline, "dea") do
      Map.put(kline, "hist", (kline["dif"] - kline["dea"]) * power)
    else
      kline
    end
  end

  def all_has_key?(list, key) do
    list |> Enum.map(&(Map.has_key?(&1, key))) |> Enum.all?()
  end
end