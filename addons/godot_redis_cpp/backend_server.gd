extends Node

var web_server: WebSocketServer = WebSocketServer.new()

@export var redis_client: RedisClient
@export var WEB_PORT: int = 8888

@export_group("JWT Configuration")
@export_file("*.pem") var private_key_path: String
@export_file("*.pem") var public_key_path: String

# --- Configurazione JWT ---
# Queste variabili dovrebbero essere inizializzate all'avvio del server.
var jwt_algorithm: JWTAlgorithm
var jwt_verifier: JWTVerifier

@export var JWT_ISSUER = "YourGameServer.com"
@export var TOKEN_VALIDITY_SECONDS = 3600 * 24 * 7 # 1 settimana

# Dizionario per le connessioni autenticate: peer_id -> user_id
var authenticated_peers: Dictionary = {}
# Dizionario per i timer di timeout per i client non autenticati
var unauthenticated_timers: Dictionary = {}
const AUTH_TIMEOUT_SECONDS = 30

# Dizionario per mappare i tipi di messaggio ai loro gestori (handlers)
# Gli handlers saranno i nodi figli
var message_handlers = {}

# Mappa per trovare rapidamente il peer_id di un utente connesso.
var user_id_to_peer_id_map: Dictionary = {}

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
	
	# Inizializza i gestori JWT dopo che sono stati aggiunti all'albero
	await get_tree().process_frame
	_initialize_jwt_handlers()

func _initialize_jwt_handlers():
	if private_key_path.is_empty() or public_key_path.is_empty():
		printerr("CRITICAL: Percorsi delle chiavi JWT privata o pubblica non impostati nel BackendServer!")
		get_tree().quit()
		return

	#var private_key_pem = FileAccess.get_file_as_string(private_key_path)
	#var public_key_pem = FileAccess.get_file_as_string(public_key_path)

	initialize_jwt(private_key_path, public_key_path)


# Metodo per inizializzare le chiavi e il verificatore JWT
func initialize_jwt(private_key_pem: String, public_key_pem: String):
	var private_key: CryptoKey = CryptoKey.new()
	var public_key: CryptoKey = CryptoKey.new()

	var res = private_key.load(private_key_pem)
	if res != OK:
		printerr("SERVER: Impossibile caricare la chiave privata PEM per JWT. Errore: ", res)
		get_tree().quit()
		return

	res = public_key.load(public_key_pem, true)
	if res != OK:
		printerr("SERVER: Impossibile caricare la chiave pubblica PEM per JWT. Errore: ", res)
		get_tree().quit()
		return
	
	# Algoritmo per firmare (usa la chiave privata)
	jwt_algorithm = JWTAlgorithmBuilder.RS256(public_key, private_key)

	
	# Verificatore per le richieste in arrivo (usa solo la chiave pubblica)
	var verify_algorithm: JWTAlgorithm = JWTAlgorithmBuilder.RSA256(public_key)
	jwt_verifier = JWT.require(verify_algorithm).with_issuer(JWT_ISSUER).build()
	print("SERVER: JWT Handler inizializzato.")

func is_token_valid(token: String) -> bool:
	if jwt_verifier == null:
		printerr("JWT Verifier non inizializzato!")
		return false
		
	if jwt_verifier.verify(token) != JWTVerifier.JWTExceptions.OK:
		return false
	
	return true

func start_server():
	# 1. Avvia la connessione con Redis
	redis_client.connect_to_redis()
	star_web_server()

func star_web_server():
	# 2. Avvia il server WEB
	var err = web_server.listen(WEB_PORT)
	if err == OK:
		print("BackendServer: in ascolto sulla porta ", WEB_PORT)
	else:
		printerr("BackendServer: Impossibile avviare il server WebSocket.", err)
		get_tree().quit()

func stop_web_server():
	web_server.stop()
	
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
	# Avvia un timer per forzare l'autenticazione entro 30 secondi.
	var timer = Timer.new()
	timer.wait_time = AUTH_TIMEOUT_SECONDS
	timer.one_shot = true
	# Usiamo una lambda per passare il peer_id al timeout
	timer.timeout.connect(func(): _on_auth_timeout(peer_id))
	add_child(timer)
	timer.start()
	unauthenticated_timers[peer_id] = timer
	
func _on_client_disconnected(peer_id: int):
	print("BackendServer: Client disconnesso: ", peer_id)
	deauthenticate_peer(peer_id) # Pulisce tutte le mappe di stato
	# Se il client si disconnette prima del timeout, ferma e rimuovi il timer.
	if unauthenticated_timers.has(peer_id):
		var timer = unauthenticated_timers[peer_id]
		timer.stop()
		timer.queue_free()
		unauthenticated_timers.erase(peer_id)

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

	# --- Nuova Logica di Autorizzazione a Livello di Connessione ---
	var user_id = authenticated_peers.get(peer_id, -1)

	# Se il messaggio non è di autenticazione e la connessione non è autenticata, rifiuta.
	if not (msg_type in ["LOGIN", "REGISTER", "RECONNECT"]) and user_id == -1:
		send_response(peer_id, "ERROR", req_id, {"success": false, "message": "Autenticazione richiesta."})
		return

	if message_handlers.has(msg_type):
		var handler = message_handlers[msg_type]
		# Passiamo l'ID utente (se autenticato) al gestore.
		handler.handle_message(peer_id, msg_type, req_id, payload, user_id)
	else:
		printerr("BackendServer: Nessun handler per il tipo '", msg_type, "' dal peer ", peer_id)

func _on_auth_timeout(peer_id: int):
	# Se il timer è ancora attivo, significa che il client non si è autenticato.
	if unauthenticated_timers.has(peer_id):
		print("SERVER: Timeout di autenticazione per il peer ", peer_id, ". Disconnessione.")
		web_server.disconnect_peer(peer_id)
		unauthenticated_timers.erase(peer_id) # Il timer verrà liberato in _on_client_disconnected

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

func authenticate_peer(peer_id: int, user_id: int):
	"""Registra una connessione (peer) come autenticata."""
	authenticated_peers[peer_id] = user_id
	user_id_to_peer_id_map[user_id] = peer_id
	# Ferma e rimuovi il timer di timeout perché l'autenticazione è avvenuta.
	if unauthenticated_timers.has(peer_id):
		var timer = unauthenticated_timers[peer_id]
		timer.stop()
		timer.queue_free()
		unauthenticated_timers.erase(peer_id)
	print("SERVER: Peer ", peer_id, " autenticato come utente ", user_id)

func deauthenticate_peer(peer_id: int):
	"""Rimuove l'autenticazione di una connessione."""
	if authenticated_peers.has(peer_id):
		var user_id = authenticated_peers[peer_id]
		user_id_to_peer_id_map.erase(user_id)
		authenticated_peers.erase(peer_id)
		print("SERVER: Peer ", peer_id, " (Utente ", user_id, ") deautenticato.")

func get_peer_id_from_user_id(user_id: int) -> int:
	"""
	Restituisce il peer_id di un utente connesso e autenticato, dato il suo user_id.
	Restituisce -1 se l'utente non è attualmente connesso.
	"""
	return user_id_to_peer_id_map.get(user_id, -1)
