# TP 2 Mini Discord

# Question 1 : Que se passe-t-il si le serveur redémarre ou si la connexion est perdue ? 

# Si le serveur redémarre ou la connexion est perdue, le(s) client(s) est/sont déconnecté(s).

# Question 2 : Qu'apporterait la gestion du suivi de processus, redémarrage automatique par rapport à votre code ?

# Cela permettrait d'isoler les rôles entre un process pour le recv_loop, un pour le send_loop et un pour la reconnexion. Cela permettrait ainsi de définir des politiques de redémarrage (one_for_one | rest_for_one) et donc de ne pas avoir à gérer chaque erreur manuellement.