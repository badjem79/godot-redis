extends Node

@export var server_url = "ws://127.0.0.1:8888" # Sostituire con wss:// e configurare Caddy/TLS per la produzione

@export var reconnect_interval_seconds = 5.0 # Intervallo tra i tentativi di riconnessione
@export var max_reconnect_attempts = 10 # Numero massimo di tentativi di riconnessione

# --- Segnali per i Moduli (es. LoginController) ---
signal connection_established
signal connection_failed
signal connection_closed

# --- Riferimenti e Stato ---
var websocket: WebSocketClient = WebSocketClient.new() # Istanza del nostro client WebSocket
var ws_connected = false
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
	add_child(reconnect_timer) # Aggiungi il timer come figlio di NetworkManager
	reconnect_timer.wait_time = reconnect_interval_seconds
	reconnect_timer.one_shot = true # Il timer si attiva una sola volta per ogni tentativo
	reconnect_timer.timeout.connect(_on_reconnect_timer_timeout)

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

	print("NetworkManager: Tentativo di connessione a ", server_url)
	var err = websocket.connect_to_url(server_url)
	if err != OK:
		printerr("NetworkManager: Impossibile avviare la connessione WebSocket. Errore: ", err)
		emit_signal("connection_failed")
		# Nota: Se la connessione iniziale fallisce, non si attiverà la riconnessione automatica
		# a meno che tu non la chiami esplicitamente qui o in un altro punto.

# --- Gestori di Eventi WebSocket ---

func _on_connection_established():
	ws_connected = true
	print("NetworkManager: Connessione stabilita!")
	current_reconnect_attempts = 0 # Reset dei tentativi di riconnessione
	reconnect_timer.stop() # Assicurati che il timer sia fermo se si riconnette con successo
	emit_signal("connection_established")

func _on_connection_closed():
	ws_connected = false
	print("NetworkManager: Connessione chiusa.")
	emit_signal("connection_closed")
	
	current_reconnect_attempts += 1
	if current_reconnect_attempts <= max_reconnect_attempts:
		print("NetworkManager: Tentativo di riconnessione #", current_reconnect_attempts, " in ", reconnect_interval_seconds, " secondi...")
		reconnect_timer.start()
	else:
		printerr("NetworkManager: Raggiunto il numero massimo di tentativi di riconnessione (", max_reconnect_attempts, ").")
		emit_signal("connection_failed") # Puoi anche creare un segnale specifico come `reconnection_failed`

func _on_reconnect_timer_timeout():
	print("NetworkManager: Timer di riconnessione scaduto. Tentativo di riconnessione...")
	connect_to_server()

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
		"payload": payload,
		"token": session_token
	}
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
