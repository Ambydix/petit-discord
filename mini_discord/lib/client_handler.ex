defmodule MiniDiscord.ClientHandler do
  require Logger

  def start(socket) do
    :gen_tcp.send(socket, "Bienvenue sur MiniDiscord!\r\n")
    pseudo = choisir_pseudo(socket)

    :gen_tcp.send(socket, "Salons disponibles : #{salons_dispo()}\r\n")
    :gen_tcp.send(socket, "Rejoins un salon (ex: general) : ")
    {:ok, salon} = :gen_tcp.recv(socket, 0)
    salon = String.trim(salon)

    rejoindre_salon(socket, pseudo, salon)
  end

  defp choisir_pseudo(socket) do
    :gen_tcp.send(socket, "Entre ton pseudo : ")
    {:ok, pseudo} = :gen_tcp.recv(socket, 0)
    pseudo = String.trim(pseudo)
    if pseudo_disponible?(pseudo) do
      reserver_pseudo(pseudo)
      pseudo
    else
      :gen_tcp.send(socket, "Ce pseudo est déjà pris, essaye-en un autre\r\n")
      choisir_pseudo(socket)
    end
  end


  defp rejoindre_salon(socket, pseudo, salon) do
    case Registry.lookup(MiniDiscord.Registry, salon) do
      [] ->
        DynamicSupervisor.start_child(
          MiniDiscord.SalonSupervisor,
          {MiniDiscord.Salon, salon})
      _ -> :ok
    end

    MiniDiscord.Salon.rejoindre(salon, self())
    MiniDiscord.Salon.broadcast(salon, "📢 #{pseudo} a rejoint ##{salon}\r\n")
    :gen_tcp.send(socket, "Tu es dans ##{salon} — écris tes messages !\r\n")

    loop(socket, pseudo, salon)
  end

  defp loop(socket, pseudo, salon) do
    receive do
      {:message, msg} ->
        :gen_tcp.send(socket, msg)
    after 0 -> :ok
    end

    case :gen_tcp.recv(socket, 0, 100) do
      {:ok, msg} ->
        msg = String.trim(msg)
        if String.at(msg,0) == "/" do
          gerer_commande(socket,pseudo,salon, msg)
        else
          MiniDiscord.Salon.broadcast(salon, "[#{pseudo}] #{msg}\r\n")
          loop(socket, pseudo, salon)
        end

      {:error, :timeout} ->
        loop(socket, pseudo, salon)

      {:error, reason} ->
        liberer_pseudo(pseudo)
        Logger.info("Client déconnecté : #{inspect(reason)}")
        MiniDiscord.Salon.broadcast(salon, "👋 #{pseudo} a quitté ##{salon}\r\n")
        MiniDiscord.Salon.quitter(salon, self())
    end
  end

  defp gerer_commande(socket, pseudo, salon, commande) do
    case commande do
      "/list" ->
        salons = MiniDiscord.Salon.lister()
        :gen_tcp.send(socket, "Salons: #{Enum.join(salons, ", ")}\r\n")
        loop(socket, pseudo, salon)

      "/join " <> nom ->
        MiniDiscord.Salon.quitter(salon, self())
        rejoindre_salon(socket, pseudo, nom)

      "/quit" ->
        MiniDiscord.Salon.quitter(salon, self())
        liberer_pseudo(pseudo)
        :gen_tcp.send(socket, "À bientôt!\r\n")
        :gen_tcp.close(socket)
        exit(:normal)
      _ ->
        :gen_tcp.send(socket, "Commande inconnue\r\n")
        loop(socket,pseudo,salon)
    end
  end


  defp salons_dispo do
    case MiniDiscord.Salon.lister() do
      [] -> "aucun (tu seras le premier !)"
      salons -> Enum.join(salons, ", ")
    end
  end

  defp pseudo_disponible?(pseudo) do
    :ets.lookup(:pseudos, pseudo) == []
  end

  defp reserver_pseudo(pseudo) do
  :ets.insert(:pseudos, {pseudo, self()})
  end

  defp liberer_pseudo(pseudo) do
    :ets.delete(:pseudos, pseudo)
  end

end
