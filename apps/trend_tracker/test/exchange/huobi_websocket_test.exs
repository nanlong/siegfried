defmodule TrendTracker.Exchange.Huobi.WebSocketTest do
  use ExUnit.Case, async: true

  alias TrendTracker.Exchange.Huobi.WebSocket, as: HuobiWebSocket

  @futures "wss://dm.huobi.vn/ws"
  @futures_auth "wss://api.btcgateway.pro/notification"
  @access_key "0e68eee0-8876fb1b-2cf93442-hrf5gdfghe"
  @secret_key "c1ffca37-657b8ed3-5a3bf04f-68600"

  test "futures ping" do
    assert {:ok, _pid} = HuobiWebSocket.start_link(@futures, [catch_binary: self()])

    assert_receive {:caught_binary, msg}, 10000
    assert Map.has_key?(msg, "ping")
  end

  test "request symbol klines" do
    assert {:ok, pid} = HuobiWebSocket.start_link(@futures, [catch_binary: self()])

    HuobiWebSocket.push(pid, %{req: "market.BTC_CQ.kline.1week"}, fn msg ->
      assert msg["status"] == "ok"
    end)

    assert_receive {:caught_binary, msg}, 1000
    assert msg["status"] == "ok"
  end

  test "sub symbol klines" do
    assert {:ok, pid} = HuobiWebSocket.start_link(@futures, [catch_binary: self()])

    HuobiWebSocket.push(pid, %{sub: "market.BTC_CQ.kline.1week", id: "test"})
    HuobiWebSocket.on_message(pid, "market.BTC_CQ.kline.1week", fn msg ->
      assert msg["ch"] == "market.BTC_CQ.kline.1week"
      assert is_map(msg["tick"])
    end)

    assert_receive {:caught_binary, msg}, 1000
    assert is_map(msg)

    assert_receive {:caught_binary, msg}, 1000
    assert is_map(msg)
  end

  test "futures auth ping" do
    assert {:ok, _pid} = HuobiWebSocket.start_link(@futures_auth, [access_key: @access_key, secret_key: @secret_key, catch_binary: self()])
    # 鉴权
    assert_receive {:caught_binary, msg}, 10000
    assert msg["op"] == "auth"
    assert msg["err-code"] == 0

    # 心跳
    assert_receive {:caught_binary, msg}, 10000
    assert msg["op"] == "ping"
  end
end