defmodule MiniDiscord.Salon do
  use GenServer

  def start_link(name) do
    GenServer.start_link(__MODULE__, %{name: name, clients: [], historique: []},
      name: via(name))
  end

  def rejoindre(salon, pid), do: GenServer.call(via(salon), {:rejoindre, pid})
  def quitter(salon, pid),   do: GenServer.call(via(salon), {:quitter, pid})
  def broadcast(salon, msg), do: GenServer.cast(via(salon), {:broadcast, msg})
  def lister do
    Registry.select(MiniDiscord.Registry, [{{:"$1", :_, :_}, [], [:"$1"]}])
  end

  def init(state), do: {:ok, state}

  def handle_call({:rejoindre, pid}, _from, state) do
    Process.monitor(pid)
    Enum.each(Enum.reverse(state.historique), fn msg -> send(pid, {:message, msg}) end)
    {:reply, :ok, %{state | clients: [pid | state.clients]}}
  end

  def handle_call({:quitter, pid}, _from, state) do
    {:reply, :ok, %{state | clients: Enum.filter(state.clients, fn x -> x != pid end)}}
  end

  def handle_cast({:broadcast, msg}, state) do
    Enum.each(state.clients, fn pid -> send(pid, {:message, msg}) end)
    {:noreply, %{state | historique: Enum.take([msg | state.historique], 10)}}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
      {:noreply, %{state | clients: Enum.filter(state.clients, fn x -> x != pid end)}}
  end

  defp via(name), do: {:via, Registry, {MiniDiscord.Registry, name}}
end
