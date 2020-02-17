defmodule Strategy.Robot.DingDing do

  def send(text, url \\ nil) do
    if url do
      Task.async(fn ->
        headers = [{"Content-Type", "application/json"}]
        message = %{msgtype: "text", text: %{content: "报告主人！#{text}"}}
        HTTPoison.post(url, Jason.encode!(message), headers)
      end)
    end
  end
end