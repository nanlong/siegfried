defmodule TrendTracker.Robot.DingDing do

  @api "https://oapi.dingtalk.com/robot/send?access_token=b9a187ce8a56665c0c6215233cc97bdd1b5c0ad8dd8c9e342a9c4416a9b219c9"

  def send(text) do
    Task.async(fn ->
      headers = [{"Content-Type", "application/json"}]
      message = %{msgtype: "text", text: %{content: text}}
      HTTPoison.post(@api, Jason.encode!(message), headers)
    end)
  end
end