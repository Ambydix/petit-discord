defmodule MiniDiscord.Client do

  def start(host, port) do
    connect_with_retry(host, port, 1)
  end

  defp connect_with_retry(host, port, attempt) do
    case :gen_tcp.connect(String.to_charlist(host), port, [:binary, packet: :line, active: false]) do
      {:ok, socket} ->
        key = receive_server_key(socket)
        rencontre(socket, key)
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

  defp rencontre(socket, key) do
    recv_print(socket, key)
    recv_print(socket, key)

    pseudo = IO.gets("") |> (fn x -> if x, do: String.trim(x), else: nil end).()
    if pseudo == nil, do: (exit(:normal))
    :gen_tcp.send(socket, pseudo <> "\r\n")

    recv_print(socket, key)
    recv_print(socket, key)

    salon = IO.gets("") |> (fn x -> if x, do: String.trim(x), else: nil end).()
    if salon == nil, do: (exit(:normal))
    :gen_tcp.send(socket, salon <> "\r\n")

    recv_print(socket, key)
  end

  defp recv_print(socket, key) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, msg} ->
        IO.write(decrypt_message(msg, key))
        msg
      {:error, reason} ->
        IO.puts("Erreur réseau : #{inspect(reason)}")
        exit(reason)
    end
  end

  defp receive_server_key(socket) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, "KEY:" <> encoded} ->
        encoded = String.trim(encoded)

        case Base.decode64(encoded) do
          {:ok, key} ->
            key

          :error ->
            IO.puts("Clé de session invalide")
            exit(:invalid_key)
        end

      {:ok, msg} ->
        IO.write(msg)
        receive_server_key(socket)

      {:error, reason} ->
        IO.puts("Erreur réseau : #{inspect(reason)}")
        exit(reason)
    end
  end

  defp receive_loop(socket, host, port, key) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, msg} ->
        IO.write(decrypt_message(msg, key))
        receive_loop(socket, host, port, key)

      {:error, reason} ->
        IO.puts("\nConnexion perdue (#{reason}). Reconnexion...")
        :gen_tcp.close(socket)
        connect_with_retry(host, port, 1)
    end
  end

  defp send_loop(socket, key) do
    case IO.gets("") do
      nil ->
        :gen_tcp.close(socket)
        exit(:normal)

      line ->
        case valider_message(line) do
          {:ok, msg} ->
            :gen_tcp.send(socket, encrypt_message(msg, key) <> "\r\n")
          {:error, reason} ->
            IO.puts("Message invalide : #{reason}")
        end
        send_loop(socket, key)
    end
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

  defp valider_message(msg) do
    msg = String.trim(to_string(msg || ""))
    cond do
      msg == "" -> {:error, "Message vide"}
      String.length(msg) > 500 -> {:error, "Message trop long (max 500 caractères)"}
      true -> {:ok, msg}
    end
  end
end
