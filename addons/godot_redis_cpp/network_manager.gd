extends Node

const TOKEN_SAVE_PATH = "user://session.dat" # Usiamo un'estensione generica

@export var server_url = "ws://127.0.0.1:8888" # Sostituire con wss:// e configurare Caddy/TLS per la produzione

@export_group("Reconnection Strategy")
@export var reconnect_base_interval_seconds = 1.0 # Intervallo di attesa iniziale in secondi.
@export var reconnect_max_interval_seconds = 30.0 # Intervallo massimo per evitare attese troppo lunghe.
@export var reconnect_backoff_factor = 1.5 # Fattore di moltiplicazione per ogni tentativo (es. 1.5, 2.0).
@export var reconnect_jitter = 0.2 # Variazione casuale per evitare sincronizzazione (es. 0.2 = ±20%).
@export var max_reconnect_attempts = 10 # Numero massimo di tentativi di riconnessione

# --- Segnali per i Moduli (es. LoginController) ---
signal connection_established
signal connection_failed
signal connection_closed
signal session_reestablished(user_data)
signal authentication_required(reason)

# --- Riferimenti e Stato ---
var websocket: WebSocketClient = WebSocketClient.new() # Istanza del nostro client WebSocket
var ws_connected = false
var ws_connecting = false
var session_token = ""
var user_data = {}

# Dizionario per i gestori di messaggi
var message_handlers = {}

var reconnect_timer: Timer
var current_reconnect_attempts = 0

var request_id_counter = 0
# Dizionario per memorizzare le callback in attesa di una risposta
var pending_requests = {} # request_id -> Callable


func _ready():
	get_parent().add_child.call_deferred(websocket)
	
	# Inizializza il timer per la riconnessione
	reconnect_timer = Timer.new()
	add_child(reconnect_timer)
	reconnect_timer.one_shot = true # Il timer si attiva una sola volta per ogni tentativo
	reconnect_timer.timeout.connect(_on_reconnect_timer_timeout)

	# Carica il token salvato, se esiste, all'avvio del gioco.
	_load_token_from_file()

	# 1. In produzione, qui configureresti il TLS per WSS
	# var cert = load("res://cert.pem")
	# websocket.tls_options = TLSOptions.client(cert)

	# 2. Connettiti ai segnali di alto livello esposti dalla nostra classe client
	websocket.connected_to_server.connect(_on_connection_established)
	websocket.connection_closed.connect(_on_connection_closed)
	websocket.message_received.connect(_on_message_received)
	
	# 4. Start connection manually
	# connect_to_server()


func connect_to_server():
	if ws_connected:
		print("NetworkManager: Già connesso.")
		emit_signal("connection_established")
		return
	ws_connecting = true
	print("NetworkManager: Tentativo di connessione a ", server_url)
	var err = websocket.connect_to_url(server_url)
	if err != OK:
		ws_connecting = false
		printerr("NetworkManager: Impossibile avviare la connessione WebSocket. Errore: ", err)
		emit_signal("connection_failed")
		# Nota: Se la connessione iniziale fallisce, non si attiverà la riconnessione automatica
		# a meno che tu non la chiami esplicitamente qui o in un altro punto.

# --- Gestori di Eventi WebSocket ---

func _on_connection_established():
	ws_connected = true
	ws_connecting = false
	print("NetworkManager: Connessione stabilita!")
	current_reconnect_attempts = 0 # Reset dei tentativi di riconnessione
	reconnect_timer.stop() # Assicurati che il timer sia fermo se si riconnette con successo
	emit_signal("connection_established")

	# --- NUOVA LOGICA DI RI-AUTENTICAZIONE AUTOMATICA ---
	# Se abbiamo un token, il NetworkManager stesso tenta di ripristinare la sessione.
	if not session_token.is_empty():
		print("NetworkManager: Connessione stabilita. Tento di ripristinare la sessione con il token.")
		var payload = {"token": session_token}
		send_message("RECONNECT", payload, _on_reconnect_result)

func _on_connection_closed():
	ws_connected = false
	print("NetworkManager: Connessione chiusa.")
	emit_signal("connection_closed")
	
	# provo a riconnettermi solo se il token di sessione non è vuoto
	if not session_token.is_empty():
		current_reconnect_attempts += 1
		if current_reconnect_attempts <= max_reconnect_attempts:
			# --- NUOVA LOGICA: Calcolo del backoff con jitter ---
			var backoff = reconnect_base_interval_seconds * pow(reconnect_backoff_factor, current_reconnect_attempts - 1)
			var delay = min(backoff, reconnect_max_interval_seconds)
			# Aggiungi jitter: una variazione casuale per desincronizzare i client
			var jitter = delay * reconnect_jitter * randf_range(-1.0, 1.0)
			var final_wait_time = delay + jitter
			
			reconnect_timer.wait_time = final_wait_time
			print("NetworkManager: Tentativo di riconnessione #%d in %.2f secondi..." % [current_reconnect_attempts, final_wait_time])
			reconnect_timer.start()
		else:
			printerr("NetworkManager: Raggiunto il numero massimo di tentativi di riconnessione (", max_reconnect_attempts, ").")
			emit_signal("connection_failed") # Puoi anche creare un segnale specifico come `reconnection_failed`

func _on_reconnect_timer_timeout():
	print("NetworkManager: Timer di riconnessione scaduto. Tentativo di riconnessione...")
	connect_to_server()

func _on_reconnect_result(payload: Dictionary):
	"""Gestisce il risultato del tentativo di riconnessione automatica."""
	if payload.get("success"):
		var received_user_data = payload.get("user_data", {})
		if received_user_data.is_empty():
			# Il server ha risposto OK ma i dati sono malformati. Trattiamolo come un fallimento.
			_handle_failed_reconnect("Dati utente non validi durante la riconnessione.")
			return
		
		# Controlla se il server ha inviato un token rinnovato
		var new_token = payload.get("token", "")
		if not new_token.is_empty():
			print("NetworkManager: Token di sessione rinnovato dal server.")
			session_token = new_token
			save_token_to_file()

		user_data = received_user_data
		emit_signal("session_reestablished", user_data)
		print("NetworkManager: Sessione ripristinata con successo.")
	else:
		var reason = payload.get("message", "Token rifiutato o scaduto.")
		_handle_failed_reconnect(reason)

func _on_message_received(message: String):
	"""
	Punto di ingresso per tutti i messaggi. Fa il parsing e inoltra
	al gestore corretto.
	"""
	var data = JSON.parse_string(message)
	if data == null:
		printerr("NetworkManager: Ricevuto JSON non valido.")
		return
	
	var msg_type = data.get("type", "")
	var req_id = data.get("request_id", "")
	var payload = data.get("payload", {})

	# Se questa è una risposta a una richiesta specifica, gestiscila qui
	if not req_id.is_empty() and pending_requests.has(req_id):
		var callback = pending_requests[req_id]
		pending_requests.erase(req_id) # Rimuovi la richiesta in attesa
		callback.call(payload) # Chiama la callback con il payload della risposta
		return # Abbiamo finito

	# Dispatching al modulo corretto
	if message_handlers.has(msg_type):
		message_handlers[msg_type].call(payload)
	else:
		print("NetworkManager: Nessun gestore per il tipo di messaggio '", msg_type, "'")


# --- API Pubblica per i Moduli ---

func save_token_to_file():
	"""Salva il token di sessione corrente in un file."""
	if session_token.is_empty():
		# Se il token è vuoto, assicurati che il file venga eliminato.
		delete_token_file()
		return

	var file = FileAccess.open(TOKEN_SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(session_token)
		print("NetworkManager: Token salvato su file.")

func delete_token_file():
	"""Elimina il file del token salvato."""
	if FileAccess.file_exists(TOKEN_SAVE_PATH):
		var err = DirAccess.remove_absolute(TOKEN_SAVE_PATH)
		if err == OK:
			print("NetworkManager: File del token eliminato.")
		else:
			printerr("NetworkManager: Impossibile eliminare il file del token, errore: ", err)

func _load_token_from_file():
	"""Carica il token da un file, se esiste."""
	if FileAccess.file_exists(TOKEN_SAVE_PATH):
		var file = FileAccess.open(TOKEN_SAVE_PATH, FileAccess.READ)
		if file:
			session_token = file.get_as_text()
			print("NetworkManager: Token caricato dal file.")

func _handle_failed_reconnect(reason: String):
	"""Logica centralizzata per gestire un fallimento di riconnessione."""
	print("NetworkManager: Ripristino sessione fallito: ", reason)
	session_token = "" # Il token non è più valido
	delete_token_file() # Eliminiamolo
	emit_signal("authentication_required", reason)

func send_message(type: String, payload: Dictionary, on_response: Callable = Callable()):
	if not ws_connected:
		printerr("NetworkManager: Impossibile inviare messaggio, non connesso.")
		if on_response.is_valid():
			# Chiama la callback con un errore
			on_response.call({"success": false, "message": "Non connesso"})
		return
	
	# Genera un ID di richiesta univoco
	request_id_counter += 1
	var req_id = str(multiplayer.get_unique_id()) + "_" + str(request_id_counter)
	
	# Se c'è una callback, memorizzala
	if on_response.is_valid():
		pending_requests[req_id] = on_response
		# Potremmo aggiungere un timer per il timeout qui
	
	var message = {
		"type": type,
		"request_id": req_id,
		"payload": payload
	}
	
	# Includi il token solo per i messaggi che lo richiedono esplicitamente.
	# Il server si basa sullo stato autenticato del peer_id per le altre richieste.
	if type == "RECONNECT":
		message["token"] = session_token
		
	websocket.send(JSON.stringify(message))

func register_handler(msg_type: String, handler_callable: Callable):
	if message_handlers.has(msg_type):
		printerr("ATTENZIONE: Handler duplicato per '", msg_type, "' sovrascritto.")
	message_handlers[msg_type] = handler_callable
	print("NetworkManager: Registrato handler per '", msg_type, "'")

func unregister_handler(msg_type: String):
	if message_handlers.has(msg_type):
		message_handlers.erase(msg_type)
		print("NetworkManager: De-registrato handler per '", msg_type, "'")
