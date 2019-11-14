defmodule Siegfried.ExchangeTest do
  use Siegfried.DataCase

  alias Siegfried.Exchange

  describe "klines" do
    alias Siegfried.Exchange.Kline

    @valid_attrs %{
      "amount" => 1489.1381752904056,
      "close" => 5875.91,
      "count" => 1020,
      "high" => 5990.0,
      "id" => 1508947200,
      "low" => 5.4e3,
      "open" => 5712.0,
      "vol" => 8509059.112322
    }
    @invalid_attrs %{"id" => 1508947200}

    def kline_fixture(attrs \\ %{}) do
      valid_attrs = Exchange.kline_from_huobi("btcusdt", "1day", @valid_attrs)

      {:ok, kline} =
        attrs
        |> Enum.into(valid_attrs)
        |> Exchange.create_kline()

      kline
    end

    test "list_klines/0 returns all klines" do
      kline = kline_fixture()
      assert Exchange.list_klines("huobi", "btcusdt", "1day") == [kline]
    end

    test "create_kline/1 with valid data creates a kline" do
      valid_attrs = Exchange.kline_from_huobi("btcusdt", "1day", @valid_attrs)
      assert {:ok, %Kline{} = kline} = Exchange.create_kline(valid_attrs)
      assert kline.close == 5875.91
      assert kline.datetime == "2017-10-26 00:00:00+08:00 CST Asia/Shanghai"
      assert kline.exchange == "huobi"
      assert kline.high == 5990.0
      assert kline.low == 5.4e3
      assert kline.open == 5712.0
      assert kline.period == "1day"
      assert kline.symbol == "btcusdt"
      assert kline.timestamp == 1508947200
    end

    test "create_kline/1 with invalid data returns error changeset" do
      invalid_attrs = Exchange.kline_from_huobi("btcusdt", "1day", @invalid_attrs)
      assert {:error, %Ecto.Changeset{}} = Exchange.create_kline(invalid_attrs)
    end
  end
end
