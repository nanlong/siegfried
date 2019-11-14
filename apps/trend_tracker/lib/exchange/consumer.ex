defmodule TrendTracker.Exchange.Consumer do
  use GenStage

  def start_link(opts \\ []) do
    state = %{subscribe_to: opts[:subscribe_to], on_message: opts[:on_message]}
    GenStage.start_link(__MODULE__, state, opts)
  end

  def init(state) do
    if state[:subscribe_to] do
      {:consumer, state, subscribe_to: state[:subscribe_to]}
    else
      {:consumer, state}
    end
  end

  def handle_events(events, _from, state) do
    if is_function(state[:subscribe_to], 1) do
      Enum.each(events, fn event -> state[:subscribe_to].(event) end)
    end
    {:noreply, [], state}
  end
end