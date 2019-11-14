defmodule TrendTracker.Exchange.Producer do
  use GenStage

  def start_link(opts \\ []) do
    GenStage.start_link(__MODULE__, %{}, opts)
  end

  def init(state) do
    {:producer, {:queue.new, 0, state}, dispatcher: GenStage.BroadcastDispatcher}
  end

  def handle_call({:event, event}, from, {queue, pending_demand, state}) do
    queue = :queue.in({from, event}, queue)
    dispatch_events(queue, pending_demand, state, [])
  end

  def handle_demand(incoming_demand, {queue, pending_demand, state}) do
    dispatch_events(queue, incoming_demand + pending_demand, state, [])
  end

  defp dispatch_events(queue, 0, state, events) do
    {:noreply, Enum.reverse(events), {queue, 0, state}}
  end

  defp dispatch_events(queue, demand, state, events) do
    case :queue.out(queue) do
      {{:value, {from, event}}, queue} ->
        GenStage.reply(from, :ok)
        dispatch_events(queue, demand - 1, state, [event | events])
      {:empty, queue} ->
        {:noreply, Enum.reverse(events), {queue, demand, state}}
    end
  end
end