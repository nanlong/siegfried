defmodule Strategy.Exchange.Okex.AccountAPI do
  alias Strategy.Exchange.Okex.Service, as: OkexService

  require Logger

  @doc """
  资金账户信息
  """
  def get_wallet(service) do
    path = "/api/account/v3/wallet"
    speed_limit = 2 / 20
    OkexService.request(service, :get, path, speed_limit)
  end

  @doc """
  单一币种账户信息
  """
  def get_wallet(service, currency) do
    path = "/api/account/v3/wallet/#{currency}"
    speed_limit = 2 / 20
    {:ok, data} = OkexService.request(service, :get, path, speed_limit)
    {:ok, Enum.find(data, fn item -> item["currency"] == String.upcase(currency) end)}
  end

  @doc """
  获取币种列表
  """
  def get_currencies(service) do
    path = "/api/account/v3/currencies"
    speed_limit = 2 / 20
    OkexService.request(service, :get, path, speed_limit)
  end

  @doc """
  OKEx站内在资金账户、交易账户和子账户之间进行资金划转
  """
  def transfer(service, currency, amount, from, to, opts \\ []) do
    path = "/api/account/v3/transfer"
    speed_limit = 2
    body = %{currency: currency, amount: amount, from: from, to: to}
    body = OkexService.optional_body(body, opts, [:sub_account, :instrument_id, :to_instrument_id])
    OkexService.request(service, :post, path, speed_limit, body: body)
  end
end