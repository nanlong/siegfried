defmodule TrendTracker.Exchange.Okex.Service do
  use GenServer

  import TrendTracker.Helper
  import TrendTracker.Exchange.Okex.Helper

  require Logger

  @recv_timeout 10_000

  # def test do
  #   alias TrendTracker.Exchange.Okex.Service, as: OkexService
  #   passphrase = "siegfried"
  #   access_key = "5015911e-169f-41a3-8d57-cbf1daf01d53"
  #   secret_key = "E8D67A0018DB8BE67B68D181CCF969EA"
  #   {:ok, pid} = OkexService.start_link("https://www.okex.com", passphrase: passphrase, access_key: access_key, secret_key: secret_key)
  #   OkexService.get(pid, "/api/account/v3/deposit/address?currency=usdt")
  # end

  def start_link(url, opts \\ []) do
    state = %{url: url, passphrase: opts[:passphrase], access_key: opts[:access_key], secret_key: opts[:secret_key]}
    GenServer.start_link(__MODULE__, state, opts)
  end

  def init(state), do: {:ok, state}

  def get(pid, path, opts \\ []) do
    GenServer.call(pid, {:get, path, opts[:query] || %{}, opts[:retry] || 0}, @recv_timeout)
  end

  def post(pid, path, opts \\ []) do
    GenServer.call(pid, {:post, path, opts[:body] || %{}, opts[:retry] || 0}, @recv_timeout)
  end

  def handle_call({:get, path, query, retry}, _from, state) do
    resp = Enum.reduce_while(0..retry, {:error, nil}, fn _x, _acc ->
      url = join_query(state[:url] <> path, query)
      headers = headers("get", path, nil, state)

      case HTTPoison.get(url, headers, recv_timeout: @recv_timeout) do
        {:ok, _} = resp -> {:halt, resp}
        resp -> {:cont, resp}
      end
    end)

    {:reply, response(resp), state}
  end

  def handle_call({:post, path, body, retry}, _from, state) do
    resp = Enum.reduce_while(0..retry, {:error, nil}, fn _x, _acc ->
      url = state[:url] <> path
      body = Jason.encode!(body || %{})
      headers = headers("post", path, body, state)

      case HTTPoison.post(url, body, headers, recv_timeout: @recv_timeout) do
        {:ok, _} = resp -> {:halt, resp}
        resp -> {:cont, resp}
      end
    end)

    {:reply, response(resp), state}
  end

  defp headers(method, path, body, state) do
    timestamp = ts() / 1000
    sign = signature(timestamp, method, path, body, state[:secret_key])

    [
      {"OK-ACCESS-PASSPHRASE", state[:passphrase]},
      {"OK-ACCESS-KEY", state[:access_key]},
      {"OK-ACCESS-SIGN", sign},
      {"OK-ACCESS-TIMESTAMP", "#{timestamp}"},
      {"Content-Type", "application/json"}
    ]
  end

  defp join_query(url, query) do
    if Enum.empty?(query) do
      url
    else
      "#{url}?#{URI.encode_query(query)}"
    end
  end

  defp response({:ok, %HTTPoison.Response{body: body}}) do
    try do
      {:ok, Jason.decode!(body)}
    rescue
      _ -> {:ok, body}
    end
  end
  defp response({:error, %HTTPoison.Error{reason: reason}}) do
    {:error, reason}
  end
end