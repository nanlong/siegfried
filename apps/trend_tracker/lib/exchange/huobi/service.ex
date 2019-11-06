defmodule TrendTracker.Exchange.Huobi.Service do
  @moduledoc """

  ## Examples

    iex> {:ok, pid} = HuobiService.start_link("https://api.huobi.vn")
    iex> {:ok, response} = HuobiService.get(pid, "/v1/common/symbols")

  """

  use GenServer

  alias TrendTracker.Exchange.Huobi.Helpers

  @recv_timeout 10000

  def start_link(url, opts \\ []) do
    state = %{url: url, access_key: opts[:access_key], secret_key: opts[:secret_key]}
    GenServer.start_link(__MODULE__, state, opts)
  end

  def init(state), do: {:ok, state}

  def get(pid, path, opts \\ []) do
    GenServer.call(pid, {:get, path, opts[:query], opts[:retry] || 1}, @recv_timeout)
  end

  def post(pid, path, opts \\ []) do
    GenServer.call(pid, {:post, path, opts[:body], opts[:retry] || 1}, @recv_timeout)
  end

  def handle_call({:get, path, query, retry}, _from, state) do
    url = state[:url] <> path
    query = query || %{}

    url = if state[:access_key] && state[:secret_key] do
      auth_params = Helpers.auth_params(state[:access_key])
      query = Map.merge(query, auth_params)
      signature = Helpers.signature(url, "get", query, state[:secret_key])
      query = Map.merge(query, %{Signature: signature})
      join_query(url, query)
    else
      join_query(url, query)
    end

    {:reply, request(:get, url, retry), state}
  end

  def handle_call({:post, path, body, retry}, _from, state) do
    url = state[:url] <> path
    body = body || %{}

    url = if state[:access_key] && state[:secret_key] do
      query = Helpers.auth_params(state[:access_key])
      signature = Helpers.signature(url, "post", query, state[:secret_key])
      query = Map.merge(query, %{Signature: signature})
      join_query(url, query)
    else
      url
    end

    {:reply, request(:post, url, body, retry), state}
  end

  defp join_query(url, query), do: if Enum.empty?(query), do: url, else: "#{url}?#{URI.encode_query(query)}"

  defp request(:get, url, retry), do: do_request(:get, url, retry, nil)
  defp request(:post, url, body, retry), do: do_request(:post, url, body, retry, nil)

  defp do_request(:get, _url, 0, response), do: response
  defp do_request(:get, url, retry, _response) when is_integer(retry) and retry > 0 do
    resp = url |> HTTPoison.get(recv_timeout: @recv_timeout) |> response()
    if elem(resp, 0) == :ok, do: resp, else: do_request(:get, url, retry - 1, resp)
  end

  defp do_request(:post, _url, _body, 0, response), do: response
  defp do_request(:post, url, body, retry, _response) when is_integer(retry) and retry > 0 do
    headers = [{"Content-Type", "application/json"}]
    resp = url |> HTTPoison.post(Jason.encode!(body), headers, recv_timeout: @recv_timeout) |> response()
    if elem(resp, 0) == :ok, do: resp, else: do_request(:post, url, body, retry - 1, resp)
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