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

    iex> url = "wss://api.btcgateway.pro/notification"
    iex> {:ok, pid} = HuobiWebSocket.start_link(url, debug: [:trace])

  """

  use WebSockex

  alias TrendTracker.Exchange.Huobi.Helper

  require Logger

  @timeout 60_000

  def start_link(url, opts \\ []) do
    state = %{
      url: url,
      access_key: opts[:access_key],
      secret_key: opts[:secret_key],
      catch_binary: opts[:catch_binary],
      on_connect: opts[:on_connect],
      bindings: [],
      sub_topics: %{},
    }
    WebSockex.start_link(url, __MODULE__, state, opts)
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

    state = Map.merge(state, %{bindings: [], sub_topics: %{}})
    Process.send_after(self(), :check_topics_timeout, @timeout)

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

  def handle_cast({:push, frame, callback}, state) do
    id = Helper.id(frame) || Helper.id()
    frame = Map.merge(frame, %{id: id, cid: id})
    sub_topics = if frame[:sub], do: Map.merge(state[:sub_topics], %{frame[:sub] => Helper.ts()}), else: state[:sub_topics]
    state = Map.merge(state, %{bindings: state[:bindings] ++ [{:id, id, callback}], sub_topics: sub_topics})
    {:reply, {:text, Jason.encode!(frame)}, state}
  end

  def handle_cast({:on_message, topic, callback}, state) do
    {:ok, Map.merge(state, %{bindings: state[:bindings] ++ [{:topic, topic, callback}]})}
  end

  def handle_cast(:close, state), do: {:close, state}
  def handle_cast({:close, code, reason}, state), do: {:close, {code, reason}, state}

  def handle_disconnect(reason, state) do
    Logger.error("Huobi websocket reconnect \nreason: #{inspect(reason)}")
    {:reconnect, state}
  end

  def handle_terminate(reason, _state) do
    Logger.error("Huobi websocket exit normal \nreason: #{inspect(reason)}")
    exit(:normal)
  end

  def handle_info(:check_topics_timeout, state) do
    topics = Map.keys(state[:sub_topics])

    if not Enum.empty?(topics) do
      ts = Helper.ts()

      topic = Enum.reduce_while(topics, nil, fn topic, _acc ->
        topic_ts = state[:sub_topics][topic]

        if topic_ts && topic_ts < ts - @timeout do
          WebSockex.cast(self(), :close)
          {:halt, topic}
        else
          {:cont, nil}
        end
      end)

      if is_nil(topic) do
        Process.send_after(self(), :check_topics_timeout, @timeout)
      end
    end

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