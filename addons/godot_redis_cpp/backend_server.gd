# BackendServer.gd
# Core server management, handling WebSocket connections, authentication, and message routing.
extends Node

var web_server: WebSocketServer = WebSocketServer.new()

@export var redis_client: RedisClient
@export var WEB_PORT: int = 8888

@export_group("JWT Configuration")
@export_file("*.pem") var private_key_path: String
@export_file("*.pem") var public_key_path: String

# --- JWT Configuration ---
var jwt_algorithm: JWTAlgorithm
var jwt_verifier: JWTVerifier

@export var JWT_ISSUER = "YourGameServer.com"
@export var TOKEN_VALIDITY_SECONDS = 3600 * 24 * 7 # 1 week

# Peer mapping: peer_id -> user_id
var authenticated_peers: Dictionary = {}
# Timeout timers for unauthenticated clients: peer_id -> Timer
var unauthenticated_timers: Dictionary = {}
const AUTH_TIMEOUT_SECONDS = 30

# Message routing: msg_type -> handler_node
var message_handlers: Dictionary = {}

# Reverse mapping: user_id -> peer_id
var user_id_to_peer_id_map: Dictionary = {}

# Signal emitted when an authenticated client disconnects
signal client_truly_disconnected(user_id)

func _ready():
	if not redis_client:
		printerr("CRITICAL ERROR: RedisClient is not configured in BackendServer!")
		get_tree().quit()

	get_parent().add_child.call_deferred(web_server)
	
	# Connect to WebSocket server signals
	web_server.client_connected.connect(_on_client_connected)
	web_server.client_disconnected.connect(_on_client_disconnected)
	web_server.message_received.connect(_on_message_received)
	
	# Initialize JWT handlers after being added to the tree
	await get_tree().process_frame
	_initialize_jwt_handlers()

func _initialize_jwt_handlers():
	if private_key_path.is_empty() or public_key_path.is_empty():
		printerr("CRITICAL: JWT key paths not set in BackendServer!")
		get_tree().quit()
		return

	initialize_jwt(private_key_path, public_key_path)

func initialize_jwt(private_key_pem_path: String, public_key_pem_path: String):
	"""Initializes crypto keys and JWT verifier."""
	var private_key: CryptoKey = CryptoKey.new()
	var public_key: CryptoKey = CryptoKey.new()

	var res = private_key.load(private_key_pem_path)
	if res != OK:
		printerr("SERVER: Failed to load private PEM key. Error: ", res)
		get_tree().quit()
		return

	res = public_key.load(public_key_pem_path, true)
	if res != OK:
		printerr("SERVER: Failed to load public PEM key. Error: ", res)
		get_tree().quit()
		return
	
	# RS256 Algorithm for signing
	jwt_algorithm = JWTAlgorithmBuilder.RS256(public_key, private_key)
	
	# RSA256 Verifier (public key only)
	var verify_algorithm: JWTAlgorithm = JWTAlgorithmBuilder.RSA256(public_key)
	jwt_verifier = JWT.require(verify_algorithm).with_issuer(JWT_ISSUER).build()
	print("SERVER: JWT Handler initialized.")

func is_token_valid(token: String) -> bool:
	if jwt_verifier == null:
		printerr("JWT Verifier not initialized!")
		return false
		
	if jwt_verifier.verify(token) != JWTVerifier.JWTExceptions.OK:
		return false
	
	return true

func start_server():
	"""Starts Redis connection and WebSocket server."""
	redis_client.connect_to_redis()
	start_web_server()

func start_web_server():
	var err = web_server.listen(WEB_PORT)
	if err == OK:
		print("BackendServer: Listening on port ", WEB_PORT)
	else:
		printerr("BackendServer: Could not start WebSocket server.", err)
		get_tree().quit()

func stop_web_server():
	web_server.stop()
	
func register_handler(handler_node: Node):
	"""Registers a handler node to receive specific message types."""
	if not handler_node.has_method("get_handled_message_types"):
		printerr("BackendServer: Node '", handler_node.name, "' lacks get_handled_message_types().")
		return
		
	var types = handler_node.get_handled_message_types()
	for msg_type in types:
		if message_handlers.has(msg_type):
			# Warning: multiple handlers for same message type is not supported
			printerr("WARNING: Duplicate handler for '", msg_type, "' overwritten by ", handler_node.name)
		message_handlers[msg_type] = handler_node
		print("BackendServer: Registered handler for '", msg_type, "': ", handler_node.name)

func unregister_handler(handler_node: Node):
	"""Unregisters all message types associated with a handler node."""
	var keys_to_remove = []
	for msg_type in message_handlers:
		if message_handlers[msg_type] == handler_node:
			keys_to_remove.append(msg_type)
			
	for msg_type in keys_to_remove:
		message_handlers.erase(msg_type)
		print("BackendServer: Unregistered handler for '", msg_type, "' from node ", handler_node.name)

# --- WebSocket Event Handlers ---

func _on_client_connected(peer_id: int):
	print("BackendServer: New client connected (ID: ", peer_id, ")")
	# Start auth timeout timer
	var timer = Timer.new()
	timer.wait_time = AUTH_TIMEOUT_SECONDS
	timer.one_shot = true
	timer.timeout.connect(func(): _on_auth_timeout(peer_id))
	add_child(timer)
	timer.start()
	unauthenticated_timers[peer_id] = timer
	
func _on_client_disconnected(peer_id: int):
	print("BackendServer: Client disconnected (ID: ", peer_id, ")")

	# Check if authenticated to emit disconnected signal
	if authenticated_peers.has(peer_id):
		client_truly_disconnected.emit(authenticated_peers[peer_id])

	deauthenticate_peer(peer_id)
	
	if unauthenticated_timers.has(peer_id):
		var timer = unauthenticated_timers[peer_id]
		timer.stop()
		timer.queue_free()
		unauthenticated_timers.erase(peer_id)

func _on_message_received(peer_id: int, message: String):
	"""Parses incoming JSON, checks auth, and routes to appropriate handler."""
	var data = JSON.parse_string(message)
	if data == null:
		send_response(peer_id, "ERROR", "", {"success": false, "message": "Invalid message format."})
		printerr("BackendServer: Invalid JSON received from peer ", peer_id)
		return
	
	var msg_type = data.get("type", "")
	var req_id = data.get("request_id", "")
	var payload = data.get("payload", {})

	if not redis_client.is_connected():
		printerr("BackendServer: Message received but Redis is not connected.")
		send_response(peer_id, "ERROR", req_id, {"success": false, "message": "Database disconnected."})
		return

	# Authorization check
	var user_id = authenticated_peers.get(peer_id, -1)
	if not (msg_type in ["LOGIN", "REGISTER", "RECONNECT"]) and user_id == -1:
		send_response(peer_id, "ERROR", req_id, {"success": false, "message": "Authentication required."})
		return

	if message_handlers.has(msg_type):
		var handler = message_handlers[msg_type]
		handler.handle_message(peer_id, msg_type, req_id, payload, user_id)
	else:
		printerr("BackendServer: No handler found for message type '", msg_type, "' from peer ", peer_id)

func _on_auth_timeout(peer_id: int):
	if unauthenticated_timers.has(peer_id):
		print("SERVER: Auth timeout for peer ", peer_id, ". Disconnecting.")
		web_server.disconnect_peer(peer_id)
		unauthenticated_timers.erase(peer_id)

# --- Public Sub-module API ---

func send_response(peer_id: int, type: String, req_id: String, payload: Dictionary):
	"""Sends a JSON response to a specific peer."""
	var message = {"type": type, "request_id": req_id, "payload": payload}
	web_server.send(peer_id, JSON.stringify(message))

func broadcast(type: String, payload: Dictionary, exclude_peer_id: int = 0):
	"""Sends a JSON message to all connected peers."""
	var message = {"type": type, "payload": payload}
	web_server.send(-exclude_peer_id, JSON.stringify(message))

func authenticate_peer(peer_id: int, user_id: int):
	"""Marks a peer connection as authenticated."""
	authenticated_peers[peer_id] = user_id
	user_id_to_peer_id_map[user_id] = peer_id
	if unauthenticated_timers.has(peer_id):
		var timer = unauthenticated_timers[peer_id]
		timer.stop()
		timer.queue_free()
		unauthenticated_timers.erase(peer_id)
	print("SERVER: Peer ", peer_id, " authenticated as user ", user_id)

func deauthenticate_peer(peer_id: int):
	"""Cleans up authentication mapping for a peer."""
	if authenticated_peers.has(peer_id):
		var user_id = authenticated_peers[peer_id]
		user_id_to_peer_id_map.erase(user_id)
		authenticated_peers.erase(peer_id)
		print("SERVER: Peer ", peer_id, " (User ", user_id, ") deauthenticated.")

func get_peer_id_from_user_id(user_id: int) -> int:
	"""Returns the peer_id for a connected user, or -1 if offline."""
	return user_id_to_peer_id_map.get(user_id, -1)
