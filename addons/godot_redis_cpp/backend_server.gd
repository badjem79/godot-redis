class_name BackendServer
extends Node

var web_server = WebSocketServer.new()

@export var redis_client: RedisClient
@export var WEB_PORT = 8888

# Dizionario per mappare i tipi di messaggio ai loro gestori (handlers)
# Gli handlers saranno i nodi figli
var message_handlers = {}
var authenticated_peers = {}

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

	# 2. Avvia il server
	var err = web_server.listen(WEB_PORT)
	if err == OK:
		print("BackendServer: in ascolto sulla porta ", WEB_PORT)
	else:
		printerr("BackendServer: Impossibile avviare il server WebSocket.")
		get_tree().quit()
	
	# 3. Registra i moduli figli (come LoginHandler, etc.)
	_register_handlers()


func _register_handlers():
	"""Scansiona i nodi figli e li registra come gestori di messaggi."""
	for child in get_children():
		if child.has_method("get_handled_message_types"):
			var types = child.get_handled_message_types()
			for msg_type in types:
				if message_handlers.has(msg_type):
					printerr("ATTENZIONE: Handler duplicato per '", msg_type, "' sovrascritto da ", child.name)
				else:
					print("Registrato handler per '", msg_type, "': ", child.name)
					message_handlers[msg_type] = child


# --- Gestori di Eventi WebSocket ---

func _on_client_connected(peer_id: int):
	print("BackendServer: Nuovo client connesso con ID: ", peer_id)

func _on_client_disconnected(peer_id: int):
	print("BackendServer: Client disconnesso: ", peer_id)
	authenticated_peers.erase(peer_id) # Rimuovi l'utente se era autenticato

func _on_message_received(peer_id: int, message: String):
	"""
	Punto di ingresso principale per tutti i messaggi.
	Fa il parsing, controlla l'autenticazione e inoltra al gestore corretto.
	"""
	var data = JSON.parse_string(message)
	if data == null:
		printerr("BackendServer: Ricevuto JSON non valido dal peer ", peer_id)
		return # Ignora pacchetti malformati
	
	var msg_type = data.get("type", "")
	var payload = data.get("payload", {})
	var token = data.get("token", "")

	# --- Logica di Autorizzazione ---
	# Se il messaggio non è per l'autenticazione, il peer deve essere autenticato.
	if not (msg_type in ["LOGIN", "REGISTER"]):
		if not _is_peer_authenticated(peer_id, token):
			send_response(peer_id, "ERROR", {"message": "Non autorizzato."})
			# Potremmo anche chiudere la connessione qui
			return
	
	# --- Dispatching al Modulo Corretto ---
	if message_handlers.has(msg_type):
		var handler = message_handlers[msg_type]
		handler.handle_message(peer_id, msg_type, payload, token)
	else:
		printerr("BackendServer: Nessun handler per il tipo '", msg_type, "' dal peer ", peer_id)


# --- API per i Moduli Figli ---

func send_response(peer_id: int, type: String, payload: Dictionary):
	"""Invia un messaggio JSON a un client specifico."""
	var message = {"type": type, "payload": payload}
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

func _is_peer_authenticated(peer_id: int, token: String) -> bool:
	"""Verifica se un peer è autenticato e il suo token è valido."""
	if not authenticated_peers.has(peer_id):
		return false
	
	# In un sistema reale, il token JWT avrebbe una scadenza e una firma da verificare.
	# Per ora, confrontiamo semplicemente il token salvato.
	return authenticated_peers[peer_id].token == token
