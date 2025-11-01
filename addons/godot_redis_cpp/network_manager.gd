class_name NetworkManager
extends Node

# --- Segnali per i Moduli (es. LoginController) ---
signal connection_established
signal connection_failed
signal connection_closed

# --- Riferimenti e Stato ---
var websocket: WebSocketClient = WebSocketClient.new() # Istanza del nostro client WebSocket
var ws_connected = false
var server_url = "ws://127.0.0.1:8888" # Sostituire con wss:// e configurare Caddy/TLS per la produzione
var session_token = ""
var user_data = {}

# Dizionario per i gestori di messaggi
var message_handlers = {}


func _ready():

	get_parent().add_child.call_deferred(websocket)
	
	# 1. In produzione, qui configureresti il TLS per WSS
	# var cert = load("res://cert.pem")
	# websocket.tls_options = TLSOptions.client(cert)

	# 2. Connettiti ai segnali di alto livello esposti dalla nostra classe client
	websocket.connected_to_server.connect(_on_connection_established)
	websocket.connection_closed.connect(_on_connection_closed)
	websocket.message_received.connect(_on_message_received)
	
	# 3. Registra i moduli figli (LoginController, etc.)
	for child in get_children():
		if child.has_method("register_self_with_network_manager"):
			child.register_self_with_network_manager()
	
	# 4. Avvia la connessione
	connect_to_server()


func connect_to_server():
	print("NetworkManager: Tentativo di connessione a ", server_url)
	var err = websocket.connect_to_url(server_url)
	if err != OK:
		printerr("NetworkManager: Impossibile avviare la connessione WebSocket.")
		emit_signal("connection_failed")

# --- Gestori di Eventi WebSocket ---

func _on_connection_established():
	ws_connected = true
	print("NetworkManager: Connessione stabilita!")
	emit_signal("connection_established")

func _on_connection_closed():
	ws_connected = false
	print("NetworkManager: Connessione chiusa.")
	emit_signal("connection_closed")

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
	var payload = data.get("payload", {})
	
	# Dispatching al modulo corretto
	if message_handlers.has(msg_type):
		message_handlers[msg_type].call(payload)
	else:
		print("NetworkManager: Nessun gestore per il tipo di messaggio '", msg_type, "'")


# --- API Pubblica per i Moduli ---

func send_message(type: String, payload: Dictionary):
	if not ws_connected:
		printerr("NetworkManager: Impossibile inviare messaggio, non connesso.")
		return
	
	var message_dict = {
		"type": type,
		"payload": payload,
		"token": session_token
	}
	var message_str = JSON.stringify(message_dict)
	websocket.send(message_str)

func register_handler(msg_type: String, handler_callable: Callable):
	if message_handlers.has(msg_type):
		printerr("ATTENZIONE: Handler duplicato per '", msg_type, "' sovrascritto.")
	message_handlers[msg_type] = handler_callable
	print("NetworkManager: Registrato handler per '", msg_type, "'")
