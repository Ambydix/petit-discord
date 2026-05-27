defmodule MiniDiscord.Client do

  def start(host, port) do
    connect_with_retry(host, port, 1)
  end

  defp connect_with_retry(host, port, attempt) do
    # TODO : Tenter :gen_tcp.connect avec les bonnes options
    # TODO : Si {:ok, socket} -> connecter(socket) puis lancer les deux loops
    # TODO : Si {:error, reason} ->
    # TODO :   Afficher "Tentative #{attempt} échouée : #{reason}"
    # TODO :   Attendre 2 secondes avec :timer.sleep(2000)
    # TODO :   Rappeler connect_with_retry(host, port, attempt + 1)
    case :gen_tcp.connect(String.to_charlist(host), port, [:binary, packet: :line, active: false]) do
      {:ok, socket} ->
        key = :crypto.strong_rand_bytes(32)
        _iv = :crypto.strong_rand_bytes(16)
        rencontre(socket)
        receiver = Task.async(fn -> receive_loop(socket, host, port, key) end)
        sender = Task.async(fn -> send_loop(socket, key) end)
        Task.await(receiver, :infinity)
        Task.await(sender, :infinity)
      {:error,reason} ->
        IO.puts("Tentative #{attempt} échouée : #{reason}")
        :timer.sleep(2000)
        connect_with_retry(host, port, attempt + 1)
      end

  end

  defp rencontre(socket) do
    recv_print(socket)
    recv_print(socket)

    pseudo = IO.gets("") |> (fn x -> if x, do: String.trim(x), else: nil end).()
    if pseudo == nil, do: (exit(:normal))
    :gen_tcp.send(socket, pseudo <> "\r\n")

    recv_print(socket)
    recv_print(socket)

    salon = IO.gets("") |> (fn x -> if x, do: String.trim(x), else: nil end).()
    if salon == nil, do: (exit(:normal))
    :gen_tcp.send(socket, salon <> "\r\n")

    recv_print(socket)
  end

  defp recv_print(socket) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, msg} ->
        IO.write(msg)
        msg
      {:error, reason} ->
        IO.puts("Erreur réseau : #{inspect(reason)}")
        exit(reason)
    end
  end

  defp receive_loop(socket, host, port, _key) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, msg} ->
        case valider_message(msg) do
          {:ok, msg} ->
            msg_recu = <<iv::binary-size(16), msg_chiffre::binary>>
            msg = :crypto.crypto_one_time(:aes_256_ctr, key, iv, msg_recu, false)
            IO.write(msg <> "\r\n")
          {:error, reason} ->
            IO.puts("Message invalide du serveur : #{reason}")
        end
        receive_loop(socket, host, port, key, iv)

      {:error, reason} ->
        IO.puts("\nConnexion perdue (#{reason}). Reconnexion...")
        :gen_tcp.close(socket)
        connect_with_retry(host, port, 1)
    end
  end

  defp send_loop(socket, _key) do
    case IO.gets("") do
      nil ->
        :gen_tcp.close(socket)
        exit(:normal)

      line ->
        case valider_message(line) do
          {:ok, msg} ->
            :gen_tcp.send(socket, msg <> "\r\n")
          {:error, reason} ->
            IO.puts("Message invalide : #{reason}")
        end
        send_loop(socket, _key)
    end
  end

  defp valider_message(msg) do
    msg = String.trim(to_string(msg || ""))
    cond do
      msg == "" -> {:error, "Message vide"}
      String.length(msg) > 500 -> {:error, "Message trop long (max 500 caractères)"}
      true -> {:ok, msg}
    end
  end
end
