defmodule TrendTracker.Exchange.Huobi.WebSocket do
  @moduledoc """

  ## 主要功能

    - 单元测试支持
    - 订阅后一分钟收不到信息，执行重连操作
    - 鉴权回调
    - on_connect 连接回调
    - push 发送信息
    - on_message 推送回调

  ## Examples

    iex> url = "wss://api.huobi.io/ws"
    iex> {:ok, pid} = HuobiWebSocket.start_link(url: url, debug: [:trace])

  """

  use WebSockex

  alias TrendTracker.Exchange.Huobi.Helper

  require Logger

  @timeout 60_000

  def start_link(opts \\ []) do
    state = %{
      url: opts[:url],
      access_key: opts[:access_key],
      secret_key: opts[:secret_key],
      catch_binary: opts[:catch_binary],
      on_connect: opts[:on_connect],
      bindings: [],
      sub_topics: %{},
      check_topics_timeout: nil,
    }
    WebSockex.start_link(opts[:url], __MODULE__, state, opts)
  end

  def handle_connect(conn, state) do
    on_connect = fn ->
      callback = state[:on_connect]

      cond do
        is_function(callback, 0) -> callback.()
        is_function(callback, 1) -> callback.(self())
        is_function(callback, 2) -> callback.(self(), state)
        is_function(callback, 3) -> callback.(self(), conn, state)
        true -> nil
      end
    end

    if state[:access_key] && state[:secret_key] do
      WebSockex.cast(self(), {:auth, fn
        %{"op" => "auth", "err-code" => 0} ->
          on_connect.()

        %{"op" => "auth", "err-code" => err_code, "err-msg" => err_msg} ->
          Logger.error("#{err_code} #{err_msg}")
      end})
    else
      on_connect.()
    end

    # 重连情况下，取消未执行的定时检查
    if is_reference(state[:check_topics_timeout]), do: Process.cancel_timer(state[:check_topics_timeout])
    state = Map.merge(state, %{bindings: [], sub_topics: %{}, check_topics_timeout: nil})

    {:ok, state}
  end

  def handle_frame({:binary, msg}, %{catch_binary: pid} = state) when is_pid(pid) do
    response = binary_msg(msg, state)
    send(pid, {:caught_binary, Helper.unzip(msg)})
    response
  end
  def handle_frame({:binary, msg}, state) do
    binary_msg(msg, state)
  end

  def handle_cast({:auth, callback}, state) do
    auth_params = Helper.auth_params(state[:access_key])
    signature = Helper.signature(state[:url], "get", auth_params, state[:secret_key])
    frame = Map.merge(auth_params, %{op: "auth", type: "api", Signature: signature})
    state = Map.merge(state, %{bindings: state[:bindings] ++ [{:topic, "auth", callback}]})
    {:reply, {:text, Jason.encode!(frame)}, state}
  end

  def handle_cast({:push, %{sub: topic} = frame, callback}, state) do
    id = Helper.id(frame) || Helper.id()
    frame = Map.merge(frame, %{id: id, cid: id})
    topics = Map.merge(state[:sub_topics], %{topic => Helper.ts()})
    state = {:id, id, callback} |> add_bindings(state) |> Map.merge(%{sub_topics: topics})

    # 订阅消息时，打开定时检查
    state = if not is_reference(state[:check_topics_timeout]) do
      refer = Process.send_after(self(), :check_topics_timeout, @timeout)
      Map.merge(state, %{check_topics_timeout: refer})
    else
      state
    end

    {:reply, {:text, Jason.encode!(frame)}, state}
  end
  def handle_cast({:push, frame, callback}, state) do
    id = Helper.id(frame) || Helper.id()
    frame = Map.merge(frame, %{id: id, cid: id})
    {:reply, {:text, Jason.encode!(frame)}, add_bindings({:id, id, callback}, state)}
  end

  def handle_cast({:on_message, topic, callback}, state) do
    {:ok, add_bindings({:topic, topic, callback}, state)}
  end

  def handle_cast(:close, state), do: {:close, state}
  def handle_cast({:close, code, reason}, state), do: {:close, {code, reason}, state}

  def handle_disconnect(reason, state) do
    Logger.error("Huobi websocket reconnect \nreason: #{inspect(reason)}")
    {:reconnect, state}
  end

  def handle_terminate(reason, state) do
    if is_reference(state[:check_topics_timeout]), do: Process.cancel_timer(state[:check_topics_timeout])
    Logger.error("Huobi websocket exit normal \nreason: #{inspect(reason)}")
    exit(:normal)
  end

  def handle_info(:check_topics_timeout, %{sub_topics: sub_topics} = state) when map_size(sub_topics) > 0 do
    ts = Helper.ts()
    topics = Map.keys(sub_topics)

    topic = Enum.reduce_while(topics, nil, fn topic, _acc ->
      topic_ts = sub_topics[topic]

      # 在预定时间内没有收到信息，主动关闭 websocket，会自动重连
      if topic_ts && topic_ts < ts - @timeout do
        WebSockex.cast(self(), :close)
        {:halt, topic}

      # 没有超时的情况
      else
        {:cont, nil}
      end
    end)

    # 没有超时的情况下，准备下一次检查
    if is_nil(topic) do
      refer = Process.send_after(self(), :check_topics_timeout, @timeout)
      {:ok, Map.merge(state, %{check_topics_timeout: refer})}

    # 有超时，websocket 会重连
    else
      {:ok, state}
    end
  end
  def handle_info(:check_topics_timeout, state) do
    {:ok, state}
  end

  def push(pid, frame, callback \\ nil) when is_map(frame) do
    WebSockex.cast(pid, {:push, frame, callback})
  end

  def on_message(pid, topic, callback) do
    WebSockex.cast(pid, {:on_message, topic, callback})
  end

  defp binary_msg(msg, state) do
    msg = :zlib.gunzip(msg)

    if String.contains?(msg, "ping") do
      {:reply, {:text, String.replace(msg, "ping", "pong")}, state}
    else
      state = msg |> Jason.decode!() |> trigger_callback(state) |> update_topics_ts(state)
      {:ok, state}
    end
  end

  def add_bindings(binding, state) do
    Map.merge(state, %{bindings: state[:bindings] ++ [binding]})
  end

  defp trigger_callback(msg, state) do
    {id, topic} = {Helper.id(msg), Helper.topic(msg)}

    state[:bindings]
    |> Enum.reverse()
    |> Enum.reduce_while(nil, fn {type, key, callback}, _acc ->
      if (type == :id && key == id && msg["status"] == "ok") || (type == :topic && key == topic) do
        cond do
          is_function(callback, 0) -> callback.()
          is_function(callback, 1) -> callback.(msg)
          is_function(callback, 2) -> callback.(msg, state)
          true -> nil
        end

        {:halt, nil}
      else
        {:cont, nil}
      end
    end)

    msg
  end

  defp update_topics_ts(%{"ch" => topic, "ts" => ts}, state) do
    if Map.has_key?(state[:sub_topics], topic) do
      Map.merge(state, %{sub_topics:  Map.merge(state[:sub_topics], %{topic => ts})})
    else
      state
    end
  end
  defp update_topics_ts(_msg, state), do: state
end