# BackendServer.gd (scena Backend.tscn)
extends Node

const WEB_PORT = 8888
var web_server = TCPServer.new()

@export var rc: RedisClient

# Dizionario per mappare i tipi di messaggio ai loro gestori (handlers)
# Gli handlers saranno i nodi figli
var message_handlers = {}
var authenticated_peers = {}

func _ready():
	# ... (avvio del server WebSocket come prima) ...
	web_server.client_connected.connect(_on_web_client_connected)
	web_server.client_disconnected.connect(_on_web_client_disconnected)
	web_server.data_received.connect(_on_web_data_received)
	
	var err = web_server.listen(WEB_PORT)
	if err == OK:
		print("Server WebSocket in ascolto sulla porta ", WEB_PORT)
	else:
		print("Errore nell'avviare il server WebSocket.")
		get_tree().quit()
		
	# Cerca e registra automaticamente tutti i nodi figli come handlers
	for child in get_children():
		if child.has_method("get_handled_message_types"):
			var types = child.get_handled_message_types()
			for msg_type in types:
				if message_handlers.has(msg_type):
					printerr("ATTENZIONE: Handler duplicato per il tipo '", msg_type, "'")
				else:
					print("Registrato handler per '", msg_type, "': ", child.name)
					message_handlers[msg_type] = child

func authenticate_peer(peer_id: int, user_id: int, token: String):
	authenticated_peers[peer_id] = {
		"user_id": user_id,
		"token": token
	}

func _on_web_data_received(id):
	var packet = web_server.get_peer(id).get_packet().get_string_from_utf8()
	var data = JSON.parse_string(packet)
	if data == null: return # Ignora pacchetti malformati
	
	var msg_type = data.get("type", "")
	var payload = data.get("payload", {})
	
	if not (msg_type in ["LOGIN", "REGISTER"]):
		if not authenticated_peers.has(id):
			send_response(id, "ERROR", {"message": "Non autorizzato."})
			return

	# Dispatching al modulo corretto
	if message_handlers.has(msg_type):
		var handler = message_handlers[msg_type]
		# Chiamiamo un metodo standard su tutti gli handlers
		handler.handle_message(id, msg_type, payload, data.get("token", ""))
	else:
		print("BackendServer: Nessun handler per il tipo di messaggio '", msg_type, "'")

# Metodo helper per gli handlers per inviare risposte
func send_response(peer_id, type, payload):
	var message = {"type": type, "payload": payload}
	web_server.get_peer(peer_id).send_text(JSON.stringify(message))
