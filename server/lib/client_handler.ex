defmodule MiniDiscord.ClientHandler do
  require Logger

  def start(socket) do
    key = :crypto.strong_rand_bytes(32)
    :gen_tcp.send(socket, "KEY:" <> Base.encode64(key) <> "\r\n")

    send_encrypted(socket, "Bienvenue sur MiniDiscord!\r\n", key)
    pseudo = choisir_pseudo(socket, key)

    send_encrypted(socket, "Salons disponibles : #{salons_dispo()}\r\n", key)
    send_encrypted(socket, "Rejoins un salon (ex: general) : \r\n", key)
    {:ok, salon} = :gen_tcp.recv(socket, 0)
    salon = String.trim(salon)

    rejoindre_salon(socket, pseudo, salon, key)
  end

  defp choisir_pseudo(socket, key) do
    send_encrypted(socket, "Entre ton pseudo : \r\n", key)
    {:ok, pseudo} = :gen_tcp.recv(socket, 0)
    pseudo = String.trim(pseudo)
    if pseudo_disponible?(pseudo) do
      reserver_pseudo(pseudo)
      pseudo
    else
      send_encrypted(socket, "Ce pseudo est déjà pris, essaye-en un autre\r\n", key)
      choisir_pseudo(socket, key)
    end
  end


  defp rejoindre_salon(socket, pseudo, salon, key) do
    case Registry.lookup(MiniDiscord.Registry, salon) do
      [] ->
        DynamicSupervisor.start_child(
          MiniDiscord.SalonSupervisor,
          {MiniDiscord.Salon, salon})
      _ -> :ok
    end

    MiniDiscord.Salon.rejoindre(salon, self())
    MiniDiscord.Salon.broadcast(salon, "📢 #{pseudo} a rejoint ##{salon}\r\n")
    send_encrypted(socket, "Tu es dans ##{salon} — écris tes messages !\r\n", key)

    loop(socket, pseudo, salon, key)
  end

  defp loop(socket, pseudo, salon, key) do
    flush_salon_messages(socket, key)

    case :gen_tcp.recv(socket, 0, 100) do
      {:ok, msg} ->
        msg = decrypt_message(msg, key)
        msg = String.trim(msg)
        if String.at(msg,0) == "/" do
          gerer_commande(socket,pseudo,salon,key, msg)
        else
          MiniDiscord.Salon.broadcast(salon, "[#{pseudo}] #{msg}\r\n")
          loop(socket, pseudo, salon, key)
        end

      {:error, :timeout} ->
        loop(socket, pseudo, salon, key)

      {:error, reason} ->
        liberer_pseudo(pseudo)
        Logger.info("Client déconnecté : #{inspect(reason)}")
        MiniDiscord.Salon.broadcast(salon, "👋 #{pseudo} a quitté ##{salon}\r\n")
        MiniDiscord.Salon.quitter(salon, self())
    end
  end

  defp flush_salon_messages(socket, key) do
    receive do
      {:message, msg} ->
        send_encrypted(socket, msg, key)
        flush_salon_messages(socket, key)
    after 0 -> :ok
    end
  end

  defp gerer_commande(socket, pseudo, salon, key, commande) do
    case commande do
      "/list" ->
        salons = MiniDiscord.Salon.lister()
        send_encrypted(socket, "Salons: #{Enum.join(salons, ", ")}\r\n", key)
        loop(socket, pseudo, salon, key)

      "/join " <> nom ->
        MiniDiscord.Salon.broadcast(salon, "👋 #{pseudo} a quitté ##{salon}\r\n")
        MiniDiscord.Salon.quitter(salon, self())
        rejoindre_salon(socket, pseudo, nom, key)

      "/quit" ->
        liberer_pseudo(pseudo)
        MiniDiscord.Salon.broadcast(salon, "👋 #{pseudo} a quitté ##{salon}\r\n")
        MiniDiscord.Salon.quitter(salon, self())
        send_encrypted(socket, "À bientôt!\r\n", key)
        :gen_tcp.close(socket)
        exit(:normal)
      _ ->
        send_encrypted(socket, "Commande inconnue\r\n", key)
        loop(socket,pseudo,salon,key)
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

  defp send_encrypted(socket, msg, key) do
    encrypted = encrypt_message(msg, key)
    :gen_tcp.send(socket, encrypted <> "\r\n")
  end

  defp encrypt_message(msg, key) do
    iv = :crypto.strong_rand_bytes(16)
    ciphertext = :crypto.crypto_one_time(:aes_256_ctr, key, iv, msg, true)
    "ENC:" <> Base.encode64(iv <> ciphertext)
  end

  defp decrypt_message(msg, key) do
    case String.starts_with?(msg, "ENC:") do
      true ->
        encrypted = String.replace_prefix(msg, "ENC:", "") |> String.trim()

        case Base.decode64(encrypted) do
          {:ok, raw} ->
            <<iv::binary-size(16), ciphertext::binary>> = raw
            :crypto.crypto_one_time(:aes_256_ctr, key, iv, ciphertext, false)

          :error ->
            msg
        end

      false ->
        msg
    end
  end

  defp reserver_pseudo(pseudo) do
  :ets.insert(:pseudos, {pseudo, self()})
  end

  defp liberer_pseudo(pseudo) do
    :ets.delete(:pseudos, pseudo)
  end

end
