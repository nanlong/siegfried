defmodule TrendTracker.Exchange.Okex.WebSocket do
  @moduledoc """

  ## Examples

    iex> url = "wss://real.okex.com:8443/ws/v3"
    iex> {:ok, pid} = OkexWebSocket.start_link(url: url, passphrase: "passphrase", access_key: "access_key", secret_key_key: "secret_key_key")

    iex> OkexWebSocket.push(pid, "ping", fn msg -> Process.send_after(self(), :ping, 5000) end)
    iex> OkexWebSocket.push(pid, %{op: "subscribe", args: ["swap/price_range:BTC-USD-SWAP"]}, fn msg -> IO.inspect(msg) end)
    iex> OkexWebSocket.on_message(pid, "swap/price_range:BTC-USD-SWAP", fn msg -> IO.inspect(msg) end)
  """
  use WebSockex

  import TrendTracker.Helper
  import TrendTracker.Exchange.Okex.Helper

  require Logger

  def start_link(opts \\ []) do
    state = %{
      url: opts[:url],
      passphrase: opts[:passphrase],
      access_key: opts[:access_key],
      secret_key_key: opts[:secret_key_key],
      catch_binary: opts[:catch_binary],
      on_connect: opts[:on_connect],
      bindings: [],
      sub_topics: %{},
      ping: nil,
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

    if state[:access_key] && state[:secret_key] && state[:passphrase] do
      timestamp = ts(:second)
      sign = signature(timestamp, "get", "/users/self/verify", nil, state[:secret_key])

      WebSockex.cast(self(), {:push, %{op: "login", args: [state[:access_key], state[:passphrase], timestamp, sign]}, fn msg ->
        if msg["success"], do: on_connect.(), else: Logger.error("Okex websocket 登录失败")
      end})
    else
      on_connect.()
    end

    if is_reference(state[:ping]), do: Process.cancel_timer(state[:ping])

    {:ok, Map.merge(state, %{ping: nil, bindings: [], sub_topics: %{}})}
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

  def handle_cast(:close, state) do
    {:close, state}
  end
  def handle_cast({:close, code, reason}, state) do
    {:close, {code, reason}, state}
  end

  def handle_info(:ping, state) do
    {:reply, {:text, "ping"}, state}
  end

  def handle_disconnect(reason, state) do
    message = "Okex websocket reconnect \nreason: #{inspect(reason)} \nstate: #{inspect(state)}"
    file_log("okex.websocket.error.log", message)
    {:reconnect, state}
  end

  def handle_terminate(reason, state) do
    message = "Okex websocket exit normal \nreason: #{inspect(reason)} \nstate: #{inspect(state)}"
    file_log("okex.websocket.error.log", message)
    exit(:normal)
  end

  def handle_frame({:binary, msg}, state) do
    msg = case Jason.decode(:zlib.unzip(msg)) do
      {:ok, data} -> data
      {:error, error} -> error.data
    end

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

    if is_reference(state[:ping]), do: Process.cancel_timer(state[:ping])
    state = Map.merge(state, %{ping: Process.send_after(self(), :ping, 5_000)})

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