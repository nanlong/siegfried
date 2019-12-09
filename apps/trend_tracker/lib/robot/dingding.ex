defmodule TrendTracker.Robot.DingDing do

  @api Application.get_env(:trend_tracker, :robot)[:dingding]

  def send(text) do
    if @api do
      Task.async(fn ->
        headers = [{"Content-Type", "application/json"}]
        message = %{msgtype: "text", text: %{content: "报告主人！#{text}"}}
        HTTPoison.post(@api, Jason.encode!(message), headers)
      end)
    end
  end
end