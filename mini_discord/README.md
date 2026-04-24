# MiniDiscord


# Question 1 : Pourquoi utilise-t-on Process.monitor/1 dans handle_call({:rejoindre}) ? 

# Process.monitor permet de surveiller le client entrant et d'éxecuter la fonction handle_info dans le cas où la connexion avec le client (et donc le processus client) n'est pas fermée proprement (avec la commande pour quitter un salon).
# Cela permet donc de gérer les déconnexions accidentelles (perte de connexion, fermeture du terminal...)

# Question 2 : Que se passe-t-il si on n'implémente pas handle_info({:DOWN, ...}) ? 

# Si handle_info n'est pas implémenté, les déconnexions accidentelles ne sont plus gérées et donc les PID de processus qui ne sont plus dans le salon sont tout de même sollicités par les messages, ce qui occasionne un comportement imprévisible dès que le broadcast est lançé

# Question 3 : Quelle est la différence entre handle_call et handle_cast ? Pourquoi broadcast est un cast ? 

# handle_call est synchrone et renvoie toujours une réponse (:reply) au contraire de handle_cast qui est asynchrone et ne renvoie pas de réponse (:noreply)

# Question 4 : Le salon redémarre-t-il après le kill ? Pourquoi ? 

# Le salon ne redémarre pas après le kill car il n'y a aucune commande permettant de gérer cette situation et de redémarer le salon

# Question 5 :