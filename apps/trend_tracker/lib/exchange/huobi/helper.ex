defmodule TrendTracker.Exchange.Huobi.Helper do

  def id do
    :microsecond
    |> :os.system_time()
    |> to_string()
    |> :erlang.md5()
    |> Base.encode64()
  end

  def id(msg) when is_map(msg) do
    msg = atom_to_string(msg)
    msg["id"] || msg["cid"]
  end

  def topic(msg) when is_map(msg) do
    msg = atom_to_string(msg)
    msg["topic"] || msg["sub"] || msg["req"] || msg["rep"] || msg["ch"] || msg["op"]
  end

  def unzip(msg) when is_binary(msg) do
    msg |> :zlib.gunzip() |> Jason.decode!()
  end

  def ts do
    :os.system_time(:millisecond)
  end

  def auth_params(access_key) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601() |> String.split(".") |> List.first()
    %{AccessKeyId: access_key, Timestamp: timestamp, SignatureMethod: "HmacSHA256", SignatureVersion: "2"}
  end

  def signature(url, method, params, secret_key) do
    uri = URI.parse(url)
    params = params |> Enum.sort() |> Enum.map(fn {k, v} -> "#{k}=#{URI.encode_www_form(v)}" end) |> Enum.join("&")
    content = "#{String.upcase(method)}\n#{uri.host}\n#{uri.path}\n#{params}"
    :sha256 |> :crypto.hmac(secret_key, content) |> Base.encode64()
  end

  # 一张合约价值，单位美元
  def contract_size(symbol) do
    if symbol |> String.downcase() |> String.starts_with?("btc"), do: 100, else: 10
  end

  defp atom_to_string(msg) do
    for {k, v} <- msg, into: %{}, do: {to_string(k), v}
  end
end