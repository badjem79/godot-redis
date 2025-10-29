extends Node

# Segnali di connessione (generici)
signal connection_established
signal connection_failed
signal connection_closed

# Dizionario per mappare i tipi di messaggio ai loro gestori (moduli)
var message_handlers = {}

var websocket = WebSocketPeer.new()
var ws_connected = false
var server_url = "ws://127.0.0.1:8888"
var session_token = ""

func _ready():
	websocket.connection_established.connect(_on_connection_established)
	websocket.connection_error.connect(_on_connection_failed)
	websocket.server_close_request.connect(_on_connection_closed)
	websocket.connection_closed.connect(_on_connection_closed)
	websocket.data_received.connect(_on_data_received)
	connect_to_server()

func connect_to_server():
	print("Tentativo di connessione a ", server_url)
	var err = websocket.connect_to_url(server_url)
	if err != OK:
		print("Impossibile iniziare la connessione WebSocket.")
		emit_signal("connection_failed")

func _process(_delta):
	# Il client WebSocket richiede il polling
	if websocket.get_connection_status() == WebSocketPeer.STATE_OPEN:
		websocket.poll()

# --- Funzioni di Gestione della Connessione ---

func _on_connection_established(_protocol = ""):
	ws_connected = true
	print("Connessione WebSocket stabilita!")
	emit_signal("connection_established")

func _on_connection_failed():
	ws_connected = false
	print("Connessione WebSocket fallita.")
	emit_signal("connection_failed")

func _on_connection_closed(_was_clean_close = false):
	ws_connected = false
	print("Connessione WebSocket chiusa.")
	emit_signal("connection_closed")
	
# --- METODI CHIAVE PER IL DISPATCHING ---

func _on_data_received():
	var packet = websocket.get_peer(1).get_packet().get_string_from_utf8()
	var data = JSON.parse_string(packet)
	if data == null: return
	
	var msg_type = data.get("type", "")
	var payload = data.get("payload", {})
	
	# Dispatching: cerca un gestore per questo tipo di messaggio
	if message_handlers.has(msg_type):
		# Chiama la funzione del gestore registrato, passando il payload
		message_handlers[msg_type].call(payload)
	else:
		print("NetworkManager: Nessun gestore per il tipo di messaggio '", msg_type, "'")

# --- API PUBBLICA ---

func send_message(type: String, payload: Dictionary):
	if not ws_connected:
		print("Non connesso.")
		return
	
	var message = {
		"type": type,
		"payload": payload,
		"token": session_token
	}
	websocket.get_peer(1).send_text(JSON.stringify(message))

# Un modulo si registra per gestire un tipo di messaggio
func register_handler(msg_type: String, handler_callable: Callable):
	message_handlers[msg_type] = handler_callable
