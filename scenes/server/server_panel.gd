extends Control

@onready var port_label = $Panel/Label2
@onready var redis_status_label = $Panel/Label4

@onready var start_button: Button = $Panel/StartButton
@onready var stop_button: Button = $Panel/StopButton
@onready var clients_list: ItemList = $ScrollContainer/ClientsList

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	port_label.text = str(BackendServer.WEB_PORT)
	start_button.pressed.connect(_start_listening)
	stop_button.pressed.connect(_stop_listening)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	if BackendServer.redis_client.is_connected:
		redis_status_label.text = "Connected"
	else:
		redis_status_label.text = "Not Connected"
		start_button.disabled = false
		stop_button.disabled = true # Se redis non è connesso, neanche il webserver dovrebbe esserlo

	if BackendServer.web_server.is_listening():
		start_button.disabled = true
		stop_button.disabled = false
	else:
		start_button.disabled = false
		stop_button.disabled = true

	# Aggiorna la lista dei client connessi
	clients_list.clear()
	var connected_peers = BackendServer.web_server.peers.keys()
	for peer_id in connected_peers:
		if BackendServer.authenticated_peers.has(peer_id):
			var user_id = BackendServer.authenticated_peers[peer_id]
			clients_list.add_item("Peer: %d (Autenticato come Utente: %d)" % [peer_id, user_id])
		else:
			clients_list.add_item("Peer: %d (In attesa di autenticazione...)" % peer_id)

func _start_listening():
	BackendServer.star_web_server()
	
func _stop_listening():
	BackendServer.stop_web_server()
