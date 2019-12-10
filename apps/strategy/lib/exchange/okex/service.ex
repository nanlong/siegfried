defmodule Strategy.Exchange.Okex.Service do
  @moduledoc """

  ## Examples

    iex> {:ok, pid} = OkexService.start_link("https://www.okex.com", passphrase: "passphrase", access_key: "access_key", secret_key: "secret_key")
    iex> OkexService.get(pid, "/api/spot/v3/instruments/btc-usdt/candles", %{start: "2019-11-26T21:31:00.000Z", end: "2019-11-27T21:31:00.000Z", granularity: 60})
  """

  use GenServer

  import Strategy.Helper
  import Strategy.Exchange.Okex.Helper

  require Logger

  @recv_timeout 10_000

  def start_link(url, opts \\ []) do
    state = %{url: url, passphrase: opts[:passphrase], access_key: opts[:access_key], secret_key: opts[:secret_key]}
    GenServer.start_link(__MODULE__, state, opts)
  end

  def init(state), do: {:ok, state}

  @doc """
  30014 请求太频繁
  30026 用户请求频率过快，超过该接口允许的限额（调用时超过频率限制）
  30030 请求接口失败，请您重试（请求接口失败，请您重试）
  34026 划转过于频繁，请降低划转频率
  """
  def request(pid, method, path, speed_limit, opts \\ []) do
    response = apply(__MODULE__, method, [pid, path, opts])

    if Application.get_env(:siegfried, :env) in [:dev, :prod] do
      file_log("okex.restapi.log", "#{response |> elem(1) |> inspect()}")
    end

    case response do
      {:ok, %{status_code: status_code, body: body}} when status_code in 200..499 ->
        case Jason.decode(body) do
          {:ok, body} ->
            case body do
              %{"code" => code} when code in [30014, 30026, 30030, 34026] ->
                Logger.info("request `#{path}` waiting #{speed_limit} seconds...")
                Process.sleep(trunc(speed_limit * 1000))
                request(pid, method, path, speed_limit, opts)

              _ -> {:ok, body}
            end

          _ ->
            response
        end

      {:ok, %{status_code: status_code}} when status_code in [504] ->
        Logger.info("request `#{path}` waiting #{speed_limit} seconds...")
        Process.sleep(trunc(speed_limit * 1000))
        request(pid, method, path, speed_limit, opts)

      _ ->
        message = response |> elem(1) |> inspect()
        Strategy.Robot.DingDing.send("Okex Rest API: #{message}")
        response
    end
  end

  def get(pid, path, opts \\ []) do
    GenServer.call(pid, {:get, path, opts[:query] || %{}, opts[:retry] || 0}, @recv_timeout)
  end

  def post(pid, path, opts \\ []) do
    GenServer.call(pid, {:post, path, opts[:body] || %{}, opts[:retry] || 0}, @recv_timeout)
  end

  def handle_call({:get, path, query, retry}, _from, state) do
    response = Enum.reduce_while(0..retry, {:error, nil}, fn _x, _acc ->
      url = join_query(state[:url] <> path, query)
      headers = headers("get", path, nil, state)

      case HTTPoison.get(url, headers, recv_timeout: @recv_timeout) do
        {:ok, _} = resp -> {:halt, resp}
        resp -> {:cont, resp}
      end
    end)

    {:reply, response, state}
  end

  def handle_call({:post, path, body, retry}, _from, state) do
    response = Enum.reduce_while(0..retry, {:error, nil}, fn _x, _acc ->
      url = state[:url] <> path
      body = Jason.encode!(body || %{})
      headers = headers("post", path, body, state)

      case HTTPoison.post(url, body, headers, recv_timeout: @recv_timeout) do
        {:ok, _} = resp -> {:halt, resp}
        resp -> {:cont, resp}
      end
    end)

    {:reply, response, state}
  end

  def optional_query(opts, keys) do
    URI.encode_query(Keyword.take(opts, keys))
  end

  def choose_one(opts, keys) do
    Enum.reduce_while(keys, nil, fn key, _acc ->
      case opts[key] do
        nil -> {:cont, nil}
        value -> {:halt, value}
      end
    end)
  end

  def optional_body(body, opts, keys) do
    Map.merge(body, Map.new(Keyword.take(opts, keys)))
  end


  defp headers(method, path, body, state) do
    if state[:access_key] && state[:secret_key] && state[:passphrase] do
      timestamp = ts() / 1000
      sign = signature(timestamp, method, path, body, state[:secret_key])

      [
        {"OK-ACCESS-PASSPHRASE", state[:passphrase]},
        {"OK-ACCESS-KEY", state[:access_key]},
        {"OK-ACCESS-SIGN", sign},
        {"OK-ACCESS-TIMESTAMP", "#{timestamp}"},
        {"Content-Type", "application/json"}
      ]
    else
      [
        {"Content-Type", "application/json"}
      ]
    end
  end

  defp join_query(url, query) do
    if Enum.empty?(query) do
      url
    else
      "#{url}?#{URI.encode_query(query)}"
    end
  end
end