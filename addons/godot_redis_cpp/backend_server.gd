extends Node

var web_server = WebSocketServer.new()

@export var redis_client: RedisClient
@export var WEB_PORT = 8888

# Dizionario per mappare i tipi di messaggio ai loro gestori (handlers)
# Gli handlers saranno i nodi figli
var message_handlers = {}
var authenticated_peers = {}
var user_id_to_peer_id_map = {}

func _ready():
	# Verifica che il client Redis sia disponibile
	if not redis_client:
		printerr("ERRORE CRITICO: RedisClient non è configurato nel BackendServer!")
		get_tree().quit()

	get_parent().add_child.call_deferred(web_server)
	
	# Connettiti ai segnali di alto livello esposti dalla nostra classe server
	web_server.client_connected.connect(_on_client_connected)
	web_server.client_disconnected.connect(_on_client_disconnected)
	web_server.message_received.connect(_on_message_received)
	
func start_server():
	# 1. Avvia la connessione con Redis
	redis_client.connect_to_redis()
	
	# 2. Avvia il server WEB
	var err = web_server.listen(WEB_PORT)
	if err == OK:
		print("BackendServer: in ascolto sulla porta ", WEB_PORT)
	else:
		printerr("BackendServer: Impossibile avviare il server WebSocket.", err)
		get_tree().quit()

func register_handler(handler_node: Node):
	"""
	Permette a un nodo gestore (es. LoginHandler) di registrarsi con il server.
	Questa funzione viene chiamata dal gestore stesso al suo _ready().
	"""
	if not handler_node.has_method("get_handled_message_types"):
		printerr("BackendServer: Il nodo '", handler_node.name, "' ha tentato di registrarsi ma non ha il metodo get_handled_message_types().")
		return
		
	var types = handler_node.get_handled_message_types()
	for msg_type in types:
		if message_handlers.has(msg_type):
			printerr("ATTENZIONE: Handler duplicato per '", msg_type, "' sovrascritto da ", handler_node.name)
		message_handlers[msg_type] = handler_node
		print("BackendServer: Registrato handler per '", msg_type, "': ", handler_node.name)

func unregister_handler(handler_node: Node):
	"""
	Rimuove un gestore dal dizionario. Chiamato da un gestore nel suo _exit_tree().
	"""
	# Usiamo un array temporaneo per le chiavi da rimuovere per evitare di modificare
	# il dizionario mentre lo stiamo iterando.
	var keys_to_remove = []
	for msg_type in message_handlers:
		if message_handlers[msg_type] == handler_node:
			keys_to_remove.append(msg_type)
			
	for msg_type in keys_to_remove:
		message_handlers.erase(msg_type)
		print("BackendServer: De-registrato handler per '", msg_type, "' dal nodo ", handler_node.name)


# --- Gestori di Eventi WebSocket ---

func _on_client_connected(peer_id: int):
	print("BackendServer: Nuovo client connesso con ID: ", peer_id)

func _on_client_disconnected(peer_id: int):
	print("BackendServer: Client disconnesso: ", peer_id)
	if authenticated_peers.has(peer_id):
		# Rimuovi da entrambe le mappe quando un utente si disconnette
		var user_id = authenticated_peers[peer_id].user_id
		authenticated_peers.erase(peer_id)
		if user_id_to_peer_id_map.has(user_id):
			user_id_to_peer_id_map.erase(user_id)

func _on_message_received(peer_id: int, message: String):
	"""
	Punto di ingresso principale per tutti i messaggi.
	Fa il parsing, controlla l'autenticazione e inoltra al gestore corretto.
	"""
	var data = JSON.parse_string(message)
	if data == null:
		send_response(peer_id, "ERROR", "", {"success": false, "message": "Messaggio non valido."})
		printerr("BackendServer: Ricevuto JSON non valido dal peer ", peer_id)
		return # Ignora pacchetti malformati
	
	var msg_type = data.get("type", "")
	var req_id = data.get("request_id", "") # <-- Recupera l'ID
	var payload = data.get("payload", {})
	var token = data.get("token", "")

	# --- Logica di Autorizzazione ---
	# Se il messaggio non è per l'autenticazione, il peer deve essere autenticato.
	if not (msg_type in ["LOGIN", "REGISTER"]):
		if not _is_peer_authenticated(peer_id, token):
			send_response(peer_id, "ERROR", req_id, {"success": false, "message": "Non autorizzato."})
			# Potremmo anche chiudere la connessione qui
			return
	
	# --- Dispatching al Modulo Corretto ---
	if message_handlers.has(msg_type):
		var handler = message_handlers[msg_type]
		handler.handle_message(peer_id, msg_type, req_id, payload, token)
	else:
		printerr("BackendServer: Nessun handler per il tipo '", msg_type, "' dal peer ", peer_id)


# --- API per i Moduli Figli ---

func send_response(peer_id: int, type: String, req_id: String, payload: Dictionary):
	"""Invia un messaggio JSON a un client specifico."""
	var message = {"type": type, "request_id": req_id, "payload": payload}
	web_server.send(peer_id, JSON.stringify(message))

func broadcast(type: String, payload: Dictionary, exclude_peer_id: int = 0):
	"""Invia un messaggio JSON a tutti i client (o a tutti tranne uno)."""
	var message = {"type": type, "payload": payload}
	# La nostra classe WebSocketServer usa 0 per broadcast e un numero negativo per escludere.
	web_server.send(-exclude_peer_id, JSON.stringify(message))

func authenticate_peer(peer_id: int, user_id: int, token: String):
	"""Registra un peer come autenticato."""
	authenticated_peers[peer_id] = {
		"user_id": user_id,
		"token": token
	}
	user_id_to_peer_id_map[user_id] = peer_id
	print("SERVER: Peer ", peer_id, " autenticato come utente ", user_id)

func deauthenticate_peer(peer_id: int):
	"""Rimuove l'autenticazione di un peer."""
	if authenticated_peers.has(peer_id):
		var user_id = authenticated_peers[peer_id].user_id
		authenticated_peers.erase(peer_id)
		if user_id_to_peer_id_map.has(user_id):
			user_id_to_peer_id_map.erase(user_id)
		print("SERVER: Peer ", peer_id, " (Utente ", user_id, ") deautenticato.")


func _is_peer_authenticated(peer_id: int, token: String) -> bool:
	"""Verifica se un peer è autenticato e il suo token è valido."""
	if not authenticated_peers.has(peer_id):
		return false
	
	# In un sistema reale, il token JWT avrebbe una scadenza e una firma da verificare.
	# Per ora, confrontiamo semplicemente il token salvato.
	return authenticated_peers[peer_id].token == token

func get_peer_id_from_user_id(user_id: int) -> int:
	"""
	Restituisce il peer_id di un utente connesso e autenticato, dato il suo user_id.
	Restituisce -1 se l'utente non è attualmente connesso.
	"""
	return user_id_to_peer_id_map.get(user_id, -1)
