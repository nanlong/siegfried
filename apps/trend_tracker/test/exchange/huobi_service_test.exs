defmodule TrendTracker.Exchange.Huobi.ServiceTest do
  use ExUnit.Case, async: true

  alias TrendTracker.Exchange.Huobi.Service, as: HuobiService

  @spot "https://api.huobi.vn"
  @contract "https://api.hbdm.vn"
  @access_key "0e68eee0-8876fb1b-2cf93442-hrf5gdfghe"
  @secret_key "c1ffca37-657b8ed3-5a3bf04f-68600"

  test "get spot symbols" do
    assert {:ok, pid} = HuobiService.start_link(@spot)
    assert {:ok, %{"status" => "ok", "data" => data}} = HuobiService.get(pid, "/v1/common/symbols")
    assert is_list(data)
  end

  test "get spot account" do
    assert {:ok, pid} = HuobiService.start_link(@spot, access_key: @access_key, secret_key: @secret_key)
    assert {:ok, %{"status" => "ok"}} = HuobiService.get(pid, "/v1/account/accounts")
  end

  test "get contract symbols" do
    assert {:ok, pid} = HuobiService.start_link(@contract)
    assert {:ok, %{"status" => "ok", "data" => data}} = HuobiService.get(pid, "/api/v1/contract_contract_info")
    assert is_list(data)
  end

  test "get contract account" do
    assert {:ok, pid} = HuobiService.start_link(@contract, access_key: @access_key, secret_key: @secret_key)
    assert {:ok, %{"status" => "ok"} = response} = HuobiService.post(pid, "/api/v1/contract_account_info")
  end

  test "get contract order history" do
    assert {:ok, pid} = HuobiService.start_link(@contract, access_key: @access_key, secret_key: @secret_key)
    body = %{symbol: "BTC", trade_type: 0, type: 1, status: 0, create_date: 90}
    assert {:ok, %{"status" => "ok"}} = HuobiService.post(pid, "/api/v1/contract_hisorders", body: body)
  end
end