defmodule TrendTracker.Exchange.Okex.WebSocket do
  @moduledoc """

  ## Examples

    iex> url = "wss://real.okex.com:8443/ws/v3"
    iex> {:ok, pid} = OkexWebSocket.start_link(url: url)

    iex> OkexWebSocket.push(pid, "ping", fn msg -> Process.send_after(self(), :ping, 5000) end)
    iex> OkexWebSocket.push(pid, %{op: "subscribe", args: ["swap/candle60s:BTC-USD-SWAP", "swap/candle60s:EOS-USD-SWAP"]}, fn msg -> IO.inspect(msg) end)
  """
  use WebSockex

  import TrendTracker.Helper
  import TrendTracker.Exchange.Okex.Helper

  require Logger

  @timeout 60_000

  # def test() do
  #   alias TrendTracker.Exchange.Okex.WebSocket, as: OkexWebSocket
  #   url = "wss://real.okex.com:8443/ws/v3"
    # api_key = "5015911e-169f-41a3-8d57-cbf1daf01d53"
    # secret = "E8D67A0018DB8BE67B68D181CCF969EA"
    # passphrase = "siegfried"
    # {:ok, pid} = OkexWebSocket.start_link(url: url, api_key: api_key, secret: secret, passphrase: passphrase, debug: [:trace])

  #   OkexWebSocket.push(pid, %{op: "subscribe", args: ["swap/account:BTC-USD-SWAP"]}, fn msg ->
  #     IO.inspect "订阅成功"
  #     IO.inspect msg
  #   end)

  #   OkexWebSocket.on_message(pid, "swap/account:BTC-USD-SWAP", fn msg ->
  #     IO.inspect "接受到新消息"
  #     IO.inspect msg
  #   end)
  # end

  def start_link(opts \\ []) do
    state = %{
      url: opts[:url],
      api_key: opts[:api_key],
      secret: opts[:secret],
      passphrase: opts[:passphrase],
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

    if state[:api_key] && state[:secret] && state[:passphrase] do
      timestamp = ts(:second)
      sign = signature(timestamp, "get", "/users/self/verify", nil, state[:secret])

      WebSockex.cast(self(), {:push, %{op: "login", args: [state[:api_key], state[:passphrase], timestamp, sign]}, fn msg ->
        if msg["success"], do: on_connect.(), else: Logger.error("Okex websocket 登录失败")
      end})
    else
      on_connect.()
    end

    # 重连情况下，取消未执行的定时检查
    if is_reference(state[:check_topics_timeout]), do: Process.cancel_timer(state[:check_topics_timeout])
    state = Map.merge(state, %{bindings: [], sub_topics: %{}, check_topics_timeout: nil})

    # 每20秒ping-pong
    push(self(), "ping", fn _ -> Process.send_after(self(), :ping, 20_000) end)

    {:ok, state}
  end

  def push(pid, frame, callback \\ nil) do
    WebSockex.cast(pid, {:push, frame, callback})
  end

  def on_message(pid, topic, callback) do
    WebSockex.cast(pid, {:on_message, topic, callback})
  end

  def handle_cast({:push, frame, callback}, state) when is_map(frame) do
    # 将map的key全部改成string类型
    frame = for {k, v} <- frame, into: %{}, do: {to_string(k), v}

    # 保存回调
    state = case frame do
      %{"op" => "login"} ->
        add_bindings({"login", nil, callback}, state)

      %{"op" => op, "args" => topics} ->
        Enum.reduce(topics, state, fn topic, state -> add_bindings({op, topic, callback}, state) end)

      true ->
        state
    end

    # 初始化订阅时间，用于检查未收到消息的时间间隔
    state = if frame["op"] == "subscribe" do
      Enum.reduce(frame["args"], state, fn topic, state ->
        topic_data = %{topic => ts()}
        %{state | sub_topics:  Map.merge(state[:sub_topics], topic_data)}
      end)
    else
      state
    end

    # 开启定时检查
    state = if frame["op"] == "subscribe" && not is_reference(state[:check_topics_timeout]) do
      refer = Process.send_after(self(), :check_topics_timeout, @timeout)
      Map.merge(state, %{check_topics_timeout: refer})
    else
      state
    end

    {:reply, {:text, Jason.encode!(frame)}, state}
  end

  def handle_cast({:push, frame, callback}, state) when is_binary(frame) do
    state = add_bindings({nil, frame, callback}, state)
    {:reply, {:text, frame}, state}
  end

  def handle_cast({:on_message, topic, callback}, state) do
    state = add_bindings({nil, topic, callback}, state)
    {:ok, state}
  end

  def handle_cast(:close, state), do: {:close, state}
  def handle_cast({:close, code, reason}, state), do: {:close, {code, reason}, state}

  def handle_disconnect(reason, state) do
    Logger.error("Okex websocket reconnect \nreason: #{inspect(reason)}")
    {:reconnect, state}
  end

  def handle_terminate(reason, state) do
    if is_reference(state[:check_topics_timeout]), do: Process.cancel_timer(state[:check_topics_timeout])
    Logger.error("Okex websocket exit normal \nreason: #{inspect(reason)}")
    exit(:normal)
  end

  def handle_frame({:binary, msg}, state) do
    msg = case Jason.decode(:zlib.unzip(msg)) do
      {:ok, data} -> data
      {:error, error} -> error.data
    end

    IO.inspect msg

    trigger_callback(msg, state)

    # 更新订阅频道收到消息的时间
    state = case msg do
      %{"table" => table, "data" => data} ->
        Enum.reduce(data, nil, fn item, _acc ->
          topic = "#{table}:#{item["instrument_id"]}"

          if Map.has_key?(state[:sub_topics], topic) do
            topic_data = %{topic => ts()}
            %{state | sub_topics:  Map.merge(state[:sub_topics], topic_data)}
          else
            state
          end
        end)

      _ -> state
    end

    {:ok, state}
  end

  def handle_info(:ping, state) do
    push(self(), "ping", fn "pong" -> Process.send_after(self(), :ping, 5000) end)
    {:ok, state}
  end

  def handle_info(:check_topics_timeout, %{sub_topics: sub_topics} = state) when map_size(sub_topics) > 0 do
    topics = Map.keys(sub_topics)

    topic = Enum.reduce_while(topics, nil, fn topic, _acc ->
      topic_ts = sub_topics[topic]

      # 在预定时间内没有收到信息，主动关闭 websocket，会自动重连
      if topic_ts && topic_ts < ts() - @timeout do
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

  defp add_bindings({op, topic, _callback} = binding, state) do
    events = if op == "unsubscribe", do: ["unsubscribe", "subscribe"], else: [op]
    bindings = Enum.reject(state[:bindings], fn {event, channel, _} -> event in events and channel == topic end)
    Map.merge(state, %{bindings: bindings ++ [binding]})
  end

  defp trigger_callback(msg, state) do
    callback = state[:bindings]
    |> Enum.reverse()
    |> Enum.reduce_while(nil, fn {op, topic, callback}, _acc ->
      case msg do
        "pong" when topic == "ping" ->
          {:halt, callback}

        %{"event" => "login"} when op == "login" ->
          {:halt, callback}

        %{"event" => event, "channel" => channel} when op == event and topic == channel ->
          {:halt, callback}

        %{"table" => table, "data" => data} when is_nil(op) ->
          callback = Enum.reduce_while(data, nil, fn msg, _acc ->
            if String.starts_with?(topic, table) && String.ends_with?(topic, msg["instrument_id"]), do: {:halt, callback}, else: {:cont, nil}
          end)

          if callback, do: {:halt, callback}, else: {:cont, nil}

        _ ->
          {:cont, nil}
      end
    end)

    cond do
      is_function(callback, 0) -> callback.()
      is_function(callback, 1) -> callback.(msg)
      is_function(callback, 2) -> callback.(msg, state)
      true -> nil
    end
  end
end