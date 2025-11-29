# LobbyHandler.gd
extends Node

func _ready():
	# Registra questo gestore con il server autoload
	BackendServer.register_handler(self)

func _exit_tree():
	BackendServer.unregister_handler(self)

func get_handled_message_types() -> Array[String]:
	return [
		# Messaggi esistenti
		"LOBBY_GET_LIST", "LOBBY_CREATE", "LOBBY_JOIN", "LOBBY_LEAVE",
		"LOBBY_SET_READY", "Lobby_START_GAME",
		
		# Nuovi messaggi per il matchmaking
		"MATCHMAKING_JOIN_QUEUE",
        "MATCHMAKING_LEAVE_QUEUE"
	]


func handle_message(peer_id: int, msg_type: String, req_id: String, payload: Dictionary, token: String):
	var user_id = BackendServer.authenticated_peers[peer_id].user_id
	
	# Un giocatore non può fare operazioni sulla lobby se è già in una partita
	var current_lobby_id = BackendServer.redis_client.hget_value("user:" + str(user_id), "current_lobby_id")
	
	match msg_type:
		"LOBBY_GET_LIST":
			_handle_get_list(peer_id, req_id)
		"LOBBY_CREATE":
			_handle_create(peer_id, user_id, req_id, payload)
		"LOBBY_JOIN":
			_handle_join(peer_id, user_id, req_id, payload, current_lobby_id)
		"LOBBY_LEAVE":
			_handle_leave(peer_id, user_id, req_id, current_lobby_id)
		"LOBBY_SET_READY":
			_handle_set_ready(peer_id, user_id, req_id, current_lobby_id, payload)
		"LOBBY_START_GAME":
			_handle_start_game(peer_id, user_id, req_id, current_lobby_id)
		"MATCHMAKING_JOIN_QUEUE":
			_handle_join_queue(peer_id, user_id, req_id, payload)
		"MATCHMAKING_LEAVE_QUEUE":
			_handle_leave_queue(peer_id, user_id, req_id,  payload)

# --- Funzioni Helper ---
func _handle_get_list(peer_id: int, req_id: String):
	"""
	Recupera la lista delle lobby pubbliche e la invia al client.
	"""
	var public_lobbies_key = "lobbies:public"

	# 1. Recupera le chiavi delle lobby dall'indice Sorted Set.
	# Usiamo ZREVRANGE per ordinarle dalla più popolata alla meno popolata.
	# Chiediamo, ad esempio, le prime 50 lobby.
	var lobby_keys = BackendServer.redis_client.zrevrange_values(public_lobbies_key, 0, 49)
	
	if lobby_keys.is_empty():
		# Nessuna lobby pubblica, invia una lista vuota.
		BackendServer.send_response(peer_id, "LOBBY_LIST_UPDATE", req_id, {"lobbies": []})
		return

	# 2. Recupera i dati di ogni lobby.
	# Per efficienza, potremmo usare una pipeline Redis. Dato che non l'abbiamo
	# ancora implementata nel plugin C++, useremo un ciclo. Per un numero
	# limitato di lobby (es. 50), la performance è comunque accettabile.
	
	var lobbies_data = []
	for lobby_key in lobby_keys:
		var lobby_info = BackendServer.redis_client.hget_all_values(lobby_key)
		if not lobby_info.is_empty() and lobby_info.get("status") == "waiting":
			# Aggiungi informazioni utili per la UI, come il numero di giocatori.
			var player_count = BackendServer.redis_client.scard_count(lobby_key + ":players")
			lobby_info["player_count"] = player_count
			
			lobbies_data.append(lobby_info)
	
	# 3. Invia la lista completa al client che ha fatto la richiesta.
	BackendServer.send_response(peer_id, "LOBBY_LIST_UPDATE", req_id, {"lobbies": lobbies_data})
	
func _broadcast_to_lobby(lobby_key: String, msg_type: String, payload: Dictionary, exclude_peer_id: int = 0):
	var player_ids = BackendServer.redis_client.smembers_keys(lobby_key + ":players")
	for id_str in player_ids:
		var peer_id = BackendServer.get_peer_id_from_user_id(int(id_str)) # Il server ha bisogno di questo helper
		if peer_id > 0 and peer_id != exclude_peer_id:
			BackendServer.send_response(peer_id, msg_type, "", payload)

# --- Gestori di Logica ---

func _handle_create(peer_id: int, user_id: int, req_id: String, payload: Dictionary):
	var new_lobby_id = BackendServer.redis_client.increment_value("global:next_lobby_id")
	var lobby_key = "lobby:" + str(new_lobby_id)
	
	var lobby_data = {
		"id": new_lobby_id,
		"name": payload.get("name", "Nuova Partita"),
		"owner_id": user_id,
		"max_players": clampi(payload.get("max_players", 2), 2, 8),
		"is_private": "1" if payload.get("private", false) else "0",
		"status": "waiting"
	}
	BackendServer.redis_client.hset_multiple_values(lobby_key, lobby_data)
	
	if not payload.get("private", false):
		BackendServer.redis_client.zadd_values("lobbies:public", {lobby_key: 1})
	
	# Fai entrare automaticamente il creatore nella lobby
	_join_lobby_logic(peer_id, user_id, req_id, lobby_key)

func _handle_join(peer_id: int, user_id: int, req_id: String, payload: Dictionary, current_lobby_id: String):
	if not current_lobby_id.is_empty(): # Già in una lobby
		BackendServer.send_response(peer_id, "LOBBY_ERROR", req_id, {"message": "Sei già in una lobby."})
		return
	
	var lobby_key = "lobby:" + str(payload.get("id"))
	# ... (Aggiungi controlli: la lobby esiste? non è piena? etc.) ...
	
	_join_lobby_logic(peer_id, user_id, req_id, lobby_key)
	
func _join_lobby_logic(peer_id: int, user_id: int, req_id: String, lobby_key: String):
	# Aggiungi il giocatore ai dati della lobby
	BackendServer.redis_client.begin_transaction()
	BackendServer.redis_client.sadd_values(lobby_key + ":players", [str(user_id)])
	BackendServer.redis_client.hset_value("user:" + str(user_id), "current_lobby_id", lobby_key)
	BackendServer.redis_client.commit_transaction()
	
	# Aggiorna il punteggio (n. giocatori) nell'indice pubblico
	var player_count = BackendServer.redis_client.scard_count(lobby_key + ":players")
	BackendServer.redis_client.zadd_values("lobbies:public", {lobby_key: player_count})
	
	# Notifica gli altri giocatori nella lobby
	_broadcast_to_lobby(lobby_key, "LOBBY_PLAYER_JOINED", {"user_id": user_id}, peer_id)
	
	# Invia al nuovo giocatore i dati completi della lobby
	var lobby_data = BackendServer.redis_client.hget_all_values(lobby_key)
	var player_ids = BackendServer.redis_client.smembers_keys(lobby_key + ":players")
	BackendServer.send_response(peer_id, "LOBBY_JOIN_SUCCESS", req_id, {"lobby_data": lobby_data, "players": player_ids})

func _handle_leave(peer_id: int, user_id: int, req_id: String, lobby_key: String):
	if lobby_key.is_empty(): return # Non è in una lobby
	
	BackendServer.redis_client.begin_transaction()
	BackendServer.redis_client.srem_values(lobby_key + ":players", [str(user_id)])
	BackendServer.redis_client.srem_values(lobby_key + ":ready_players", [str(user_id)])
	BackendServer.redis_client.hdel_values("user:" + str(user_id), ["current_lobby_id"]) # Assumendo un hdel_values
	BackendServer.redis_client.commit_transaction()

	# Notifica gli altri
	_broadcast_to_lobby(lobby_key, "LOBBY_PLAYER_LEFT", {"user_id": user_id})
	BackendServer.send_response(peer_id, "LOBBY_LEAVE_SUCCESS", req_id, {})
	
	var player_count = BackendServer.redis_client.scard_count(lobby_key + ":players")
	if player_count == 0:
		BackendServer.redis_client.del_keys([lobby_key]) # Cancella la lobby se è vuota
		BackendServer.redis_client.zrem_values("lobbies:public", [lobby_key])
	else:
		# Aggiorna l'indice
		BackendServer.redis_client.zadd_values("lobbies:public", {lobby_key: player_count})
		# ... (logica per riassegnare l'owner se necessario) ...

func _handle_set_ready(peer_id: int, user_id: int, req_id: String, lobby_key: String, payload: Dictionary):
	var is_ready = payload.get("ready", false)
	if is_ready:
		BackendServer.redis_client.sadd_values(lobby_key + ":ready_players", [str(user_id)])
	else:
		BackendServer.redis_client.srem_values(lobby_key + ":ready_players", [str(user_id)])
		
	_broadcast_to_lobby(lobby_key, "LOBBY_PLAYER_READY", {"user_id": user_id, "is_ready": is_ready})

func _handle_start_game(peer_id: int, user_id: int, req_id: String, lobby_key: String):
	var lobby_data = BackendServer.redis_client.hget_all_values(lobby_key)
	if int(lobby_data.get("owner_id")) != user_id:
		# Solo l'owner può avviare
		return
		
	var players = BackendServer.redis_client.smembers_keys(lobby_key + ":players")
	var ready_players = BackendServer.redis_client.smembers_keys(lobby_key + ":ready_players")
	
	# Tutti devono essere pronti (tranne forse l'owner) e ci deve essere un n. minimo di giocatori
	if players.size() < 2 or players.size() != ready_players.size():
		BackendServer.send_response(peer_id, "LOBBY_ERROR", req_id, {"message": "Non tutti i giocatori sono pronti."})
		return
		
	# Avvia la partita
	BackendServer.redis_client.hset_value(lobby_key, "status", "in_game")
	BackendServer.redis_client.zrem_values("lobbies:public", [lobby_key]) # Rimuovi la lobby dalla lista pubblica
	
	# Qui creeresti un GameInstance, un nuovo GameObject di tipo "game"
	# e notificheresti i giocatori.
	_broadcast_to_lobby(lobby_key, "LOBBY_GAME_START", {"game_id": "game:123"})

func _handle_join_queue(peer_id: int, user_id: int, req_id: String, payload: Dictionary):
	# Controlla se il giocatore è già in una lobby o in un'altra coda
	var current_lobby_key = BackendServer.redis_client.hget_value("user:" + str(user_id), "current_lobby_id")
	if not current_lobby_key.is_empty():
		BackendServer.send_response(peer_id, "LOBBY_ERROR", req_id, {"message": "Sei già in una lobby o in coda."})
		return

	var matchmaking_type = payload.get("type", "default_1v1")
	var queue_key = "matchmaking:queue:" + matchmaking_type
	var max_players_for_mode = 2 # Questo potrebbe essere caricato da una configurazione

	# --- Logica di Abbinamento ---
	# Cerca una lobby di matchmaking esistente con posti liberi.
	# Per una partita 1v1, cerchiamo una lobby con esattamente 1 giocatore (score = 1).
	# Usiamo ZRANGE con `start=0, stop=0` per prendere solo il primo elemento (il più vecchio).
	var available_lobbies = BackendServer.redis_client.zrange_values(queue_key, 0, 0)
	
	var target_lobby_key = ""
	if not available_lobbies.is_empty():
		# Trovata una lobby! Il giocatore si unirà a questa.
		target_lobby_key = available_lobbies[0]
		print("SERVER: Matchmaking - Trovata lobby esistente ", target_lobby_key, " per utente ", user_id)
	else:
		# Nessuna lobby adatta trovata, ne creiamo una nuova per questo giocatore.
		print("SERVER: Matchmaking - Nessuna lobby adatta. Ne creo una nuova per utente ", user_id)
		
		var new_lobby_id = BackendServer.redis_client.increment_value("global:next_lobby_id")
		target_lobby_key = "lobby:" + str(new_lobby_id)
		
		var lobby_data = {
			"id": new_lobby_id,
			"name": "Matchmaking Game #" + str(new_lobby_id),
			"owner_id": -1, #system
			"max_players": max_players_for_mode,
			"is_private": "1", # Le lobby di matchmaking sono sempre private
			"status": "matching",
			"matchmaking_type": matchmaking_type
		}
		BackendServer.redis_client.hset_multiple_values(target_lobby_key, lobby_data)
		
		# Aggiungi la nuova lobby, vuota, alla coda di matchmaking. Lo score è il n. di giocatori.
		BackendServer.redis_client.zadd_values(queue_key, {target_lobby_key: 0})

	# --- Logica di Unione e Avvio Partita ---
	
	# 1. Fai entrare il giocatore nella lobby (riusiamo la logica esistente)
	# Assicurati che _join_lobby_logic sia disponibile nel tuo script
	_join_lobby_logic(peer_id, user_id, req_id, target_lobby_key)
	
	# Il client riceverà un LOBBY_JOIN_SUCCESS e potrà mostrare una UI "In coda..."
	
	# 2. Dopo l'unione, aggiorna lo score della lobby nella coda
	var player_count = BackendServer.redis_client.scard_count(target_lobby_key + ":players")
	BackendServer.redis_client.zadd_values(queue_key, {target_lobby_key: player_count})
	
	# 3. Controlla se la lobby è piena e la partita può iniziare
	if player_count >= max_players_for_mode:
		print("SERVER: Matchmaking - Lobby ", target_lobby_key, " è piena. Avvio partita.")
		
		# Rimuovi la lobby dalla coda di matchmaking, non può più accettare giocatori
		BackendServer.redis_client.zrem_values(queue_key, [target_lobby_key])
		
		# Avvia la partita (riusiamo la logica di avvio)
		# Il "motivo" o l'iniziatore è il sistema
		_handle_start_game(peer_id, -1, req_id, target_lobby_key)


func _handle_leave_queue(peer_id: int, user_id: int, req_id: String, payload: Dictionary):
	"""
	Rimuove un giocatore da una coda di matchmaking.
	Questa funzione riutilizza la logica generica di uscita da una lobby.
	"""
	var current_lobby_key = BackendServer.redis_client.hget_value("user:" + str(user_id), "current_lobby_id")
	
	if current_lobby_key.is_empty():
		# L'utente non è in nessuna lobby/coda, quindi non c'è niente da fare.
		return

	var lobby_data = BackendServer.redis_client.hget_all_values(current_lobby_key)
	var matchmaking_type = lobby_data.get("matchmaking_type")

	# Verifica che l'utente stia effettivamente uscendo da una coda di matchmaking e non da una lobby normale
	if not matchmaking_type or matchmaking_type.is_empty():
		BackendServer.send_response(peer_id, "LOBBY_ERROR", req_id, {"message": "Non sei in una coda di matchmaking."})
		return
		
	print("SERVER: Matchmaking - L'utente ", user_id, " sta uscendo dalla coda.")
	# Chiamiamo la funzione generica per uscire da una lobby
	_handle_leave(peer_id, user_id, req_id, current_lobby_key)
