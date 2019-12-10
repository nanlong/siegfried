defmodule Strategy.Exchange.Okex.Helper do

  def signature(timestamp, method, request_path, body, secret_key) do
    body = if is_nil(body) || body == "{}", do: "", else: body
    message = "#{timestamp}#{String.upcase(method)}#{request_path}#{body}"
    :sha256 |> :crypto.hmac(secret_key, message) |> Base.encode64()
  end
end