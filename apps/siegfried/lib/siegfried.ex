defmodule Siegfried do
  @moduledoc """
  Siegfried keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  alias Siegfried.Exchange
  alias TrendTracker.Exchange.Huobi.History, as: HuobiHistory

  def huobi_history(market, symbol, period) do
    {:ok, pid} = HuobiHistory.start_link(market, symbol, period)
    HuobiHistory.on_message(pid, fn message ->
      attrs = Exchange.kline_from_huobi(symbol, period, message)
      Exchange.create_kline(attrs)
    end)
    HuobiHistory.start(pid)
  end
end
