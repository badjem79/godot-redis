# LobbyHandler.gd
# Handles server-side lobby logic including creation, joining, leaving, and matchmaking.
extends Node

const RECONNECTION_TIMEOUT_SECONDS = 60.0 # Reconnection grace period

func _ready():
	# Register this handler with the BackendServer autoload
	BackendServer.register_handler(self)
	BackendServer.client_truly_disconnected.connect(_handle_client_disconnected)

func _exit_tree():
	BackendServer.unregister_handler(self)

func get_handled_message_types() -> Array[String]:
	return [
		"LOBBY_GET_LIST", "LOBBY_CREATE", "LOBBY_JOIN", "LOBBY_LEAVE",
		"LOBBY_SET_READY", "LOBBY_START_GAME",
		"MATCHMAKING_JOIN_QUEUE",
        "MATCHMAKING_LEAVE_QUEUE"
	]

func handle_message(peer_id: int, msg_type: String, req_id: String, payload: Dictionary, user_id: int):
	# Users cannot perform lobby operations if they are already in a game
	var current_lobby_id = BackendServer.redis_client.hget_value("user:" + str(user_id), "current_lobby_id")
	
	match msg_type:
		"LOBBY_GET_LIST":
			_handle_get_list(peer_id, req_id)
		"LOBBY_CREATE":
			_handle_create(peer_id, user_id, req_id, payload, current_lobby_id)
		"LOBBY_JOIN":
			_handle_join(peer_id, user_id, req_id, payload, current_lobby_id)
		"LOBBY_LEAVE":
			_handle_leave(peer_id, user_id, req_id, current_lobby_id)
		"LOBBY_SET_READY":
			_handle_set_ready(peer_id, user_id, req_id, current_lobby_id, payload)
		"LOBBY_START_GAME":
			_handle_start_game(peer_id, user_id, req_id, current_lobby_id)
		"MATCHMAKING_JOIN_QUEUE":
			_handle_join_queue(peer_id, user_id, req_id, payload)
		"MATCHMAKING_LEAVE_QUEUE":
			_handle_leave_queue(peer_id, user_id, req_id, payload)

# --- Helper Functions ---

func _get_public_lobbies_data() -> Array:
	"""Fetches and formats the list of public lobbies."""
	var public_lobbies_key = "lobbies:public"
	# Retrieve lobby keys from the Sorted Set, ordered by player count (descending).
	# We fetch, for example, the first 50 lobbies.
	var lobby_keys = BackendServer.redis_client.zrevrange_values(public_lobbies_key, 0, 49)
	
	var lobbies_data = []
	for lobby_key in lobby_keys:
		var lobby_info = BackendServer.redis_client.hget_all_values(lobby_key)
		if not lobby_info.is_empty() and lobby_info.get("status") in ["waiting", "matching"]:
			# Add useful info for the UI, like player count and player list.
			var player_ids = BackendServer.redis_client.smembers_keys(lobby_key + ":players")
			lobby_info["player_count"] = player_ids.size()
			lobby_info["players"] = _get_players_info(player_ids)
			lobbies_data.append(lobby_info)
	return lobbies_data

func _handle_get_list(peer_id: int, req_id: String):
	"""Retrieves the list of public lobbies and sends it to the client."""
	var lobbies_data = _get_public_lobbies_data()
	BackendServer.send_response(peer_id, "LOBBY_LIST_UPDATE", req_id, {"lobbies": lobbies_data})

func _get_players_info(player_ids: Array) -> Array:
	"""Fetches usernames for a list of user IDs."""
	var players_info = []
	for id_str in player_ids:
		var username = BackendServer.redis_client.hget_value("user:" + id_str, "username")
		if username.is_empty():
			username = "Player " + id_str
		players_info.append({"id": int(id_str), "username": username})
	return players_info

func _broadcast_to_lobby(lobby_key: String, msg_type: String, payload: Dictionary, exclude_peer_id: int = 0):
	"""Sends a message to all players in a specific lobby."""
	var player_ids = BackendServer.redis_client.smembers_keys(lobby_key + ":players")
	for id_str in player_ids:
		var peer_id = BackendServer.get_peer_id_from_user_id(int(id_str))
		if peer_id > 0 and peer_id != exclude_peer_id:
			BackendServer.send_response(peer_id, msg_type, "", payload)

func _broadcast_lobby_list_update():
	"""Broadcasts the updated public lobby list to all connected clients."""
	var lobbies_data = _get_public_lobbies_data()
	# Use broadcast to send to everyone
	BackendServer.broadcast("LOBBY_LIST_UPDATE", {"lobbies": lobbies_data})

# --- Logic Handlers ---

func _handle_create(peer_id: int, user_id: int, req_id: String, payload: Dictionary, current_lobby_id: String):
	if not current_lobby_id.is_empty(): # Already in a lobby
		BackendServer.send_response(peer_id, "LOBBY_ERROR", req_id, {"message": "You are already in a lobby."})
		return

	var new_lobby_id = BackendServer.redis_client.increment_value("global:next_lobby_id")
	var lobby_key = "lobby:" + str(new_lobby_id)
	
	var lobby_data = {
		"id": new_lobby_id,
		"name": payload.get("name", "New Match"),
		"owner_id": user_id,
		"max_players": clampi(payload.get("max_players", 2), 2, 8),
		"is_private": "1" if payload.get("private", false) else "0",
		"status": "waiting"
	}
	BackendServer.redis_client.hset_multiple_values(lobby_key, lobby_data)
	
	if not payload.get("private", false):
		BackendServer.redis_client.zadd_values("lobbies:public", {lobby_key: 1})
	
	# Automatically join the creator to the lobby
	_join_lobby_logic(peer_id, user_id, req_id, lobby_key)
	
	# Notify everyone about the change in the lobby list
	_broadcast_lobby_list_update()

func _handle_join(peer_id: int, user_id: int, req_id: String, payload: Dictionary, current_lobby_id: String):
	if not current_lobby_id.is_empty(): # Already in a lobby
		BackendServer.send_response(peer_id, "LOBBY_ERROR", req_id, {"message": "You are already in a lobby."})
		return
	
	var lobby_key = "lobby:" + str(payload.get("id"))
	if not BackendServer.redis_client.exists(lobby_key):
		BackendServer.send_response(peer_id, "LOBBY_ERROR", req_id, {"message": "Lobby does not exist."})
		return
	
	# TODO: Add lobby capacity check

	
	_join_lobby_logic(peer_id, user_id, req_id, lobby_key)
	
func _join_lobby_logic(peer_id: int, user_id: int, req_id: String, lobby_key: String):
	# Add player to lobby data
	BackendServer.redis_client.begin_transaction()
	BackendServer.redis_client.sadd_values(lobby_key + ":players", [str(user_id)])
	BackendServer.redis_client.hset_value("user:" + str(user_id), "current_lobby_id", lobby_key)
	BackendServer.redis_client.commit_transaction()
	
	# Update player count in public index
	var player_count = BackendServer.redis_client.scard_count(lobby_key + ":players")
	BackendServer.redis_client.zadd_values("lobbies:public", {lobby_key: player_count})
	
	# Notify other players in the lobby
	var username = BackendServer.redis_client.hget_value("user:" + str(user_id), "username")
	if username.is_empty(): username = "Player " + str(user_id)
	
	_broadcast_to_lobby(lobby_key, "LOBBY_PLAYER_JOINED", {"user_id": user_id, "username": username}, peer_id)
	_broadcast_lobby_list_update()
	
	# Send full lobby data to the joining player
	var lobby_data = BackendServer.redis_client.hget_all_values(lobby_key)
	var player_ids = BackendServer.redis_client.smembers_keys(lobby_key + ":players")
	var players_info = _get_players_info(player_ids)
	BackendServer.send_response(peer_id, "LOBBY_JOIN_SUCCESS", req_id, {"lobby_data": lobby_data, "players": players_info})

func _handle_leave(peer_id: int, user_id: int, req_id: String, lobby_key: String):
	if lobby_key.is_empty(): return
	
	# Fetch owner ID before leaving
	var owner_id = int(BackendServer.redis_client.hget_value(lobby_key, "owner_id"))
	
	BackendServer.redis_client.begin_transaction()
	BackendServer.redis_client.srem_values(lobby_key + ":players", [str(user_id)])
	BackendServer.redis_client.srem_values(lobby_key + ":ready_players", [str(user_id)])
	BackendServer.redis_client.hdel_values("user:" + str(user_id), ["current_lobby_id"])
	BackendServer.redis_client.commit_transaction()

	# Notify others
	_broadcast_to_lobby(lobby_key, "LOBBY_PLAYER_LEFT", {"user_id": user_id})
	
	if peer_id > 0:
		BackendServer.send_response(peer_id, "LOBBY_LEAVE_SUCCESS", req_id, {})
	
	var player_ids = BackendServer.redis_client.smembers_keys(lobby_key + ":players")
	var player_count = player_ids.size()
	
	if player_count == 0:
		print("SERVER: Lobby ", lobby_key, " is empty and will be deleted.")
		BackendServer.redis_client.del_keys([lobby_key, lobby_key + ":players", lobby_key + ":ready_players"])
		BackendServer.redis_client.zrem_values("lobbies:public", [lobby_key])
		BackendServer.redis_client.zrem_values("matchmaking:queue:default_1v1", [lobby_key])
	else:
		# Update index
		BackendServer.redis_client.zadd_values("lobbies:public", {lobby_key: player_count})
		
		# Handle Owner Reassignment
		if user_id == owner_id:
			var new_owner_id = int(player_ids[0])
			BackendServer.redis_client.hset_value(lobby_key, "owner_id", str(new_owner_id))
			print("SERVER: Owner left. Reassigning owner to user ", new_owner_id)
			_broadcast_to_lobby(lobby_key, "LOBBY_OWNER_CHANGED", {"new_owner_id": new_owner_id})
		
		# Recycle Matchmaking Lobby: If still matching, ensure it's in the queue
		var mm_type = BackendServer.redis_client.hget_value(lobby_key, "matchmaking_type")
		var status = BackendServer.redis_client.hget_value(lobby_key, "status")
		if mm_type and not mm_type.is_empty() and status == "matching":
			BackendServer.redis_client.zadd_values("matchmaking:queue:" + mm_type, {lobby_key: player_count})

	# Broadcast final state to everyone
	_broadcast_lobby_list_update()

func _handle_set_ready(peer_id: int, user_id: int, req_id: String, lobby_key: String, payload: Dictionary):
	var is_ready = payload.get("ready", false)
	if is_ready:
		BackendServer.redis_client.sadd_values(lobby_key + ":ready_players", [str(user_id)])
	else:
		BackendServer.redis_client.srem_values(lobby_key + ":ready_players", [str(user_id)])
		
	_broadcast_to_lobby(lobby_key, "LOBBY_PLAYER_READY", {"user_id": user_id, "is_ready": is_ready})

func _handle_start_game(peer_id: int, user_id: int, req_id: String, lobby_key: String):
	var lobby_data = BackendServer.redis_client.hget_all_values(lobby_key)
	if int(lobby_data.get("owner_id")) != user_id:
		return
		
	var players = BackendServer.redis_client.smembers_keys(lobby_key + ":players")
	var ready_players = BackendServer.redis_client.smembers_keys(lobby_key + ":ready_players")
	
	# Minimum players required and everyone must be ready
	if players.size() < 2 or players.size() != ready_players.size():
		BackendServer.send_response(peer_id, "LOBBY_ERROR", req_id, {"message": "Not all players are ready."})
		return
		
	# Start game
	BackendServer.redis_client.hset_value(lobby_key, "status", "in_game")
	BackendServer.redis_client.zrem_values("lobbies:public", [lobby_key])
	
	# --- Shared GameObject Creation ---
	# Create a shared Game Instance object
	var obj_handler = BackendServer.message_handlers.get("GAMEOBJECT_CREATE")
	var game_id = ""
	if obj_handler:
		var initial_data = {
			"lobby_id": lobby_key,
			"read_perm": 1, # OWNER (Server)
			"write_perm": 1 # OWNER (Server)
		}
		# Note: In a real scenario, you might set read_perm to CUSTOM and add ACLs
		# But since this is a shared object, lets use ReadPerm.CUSTOM
		initial_data["read_perm"] = -1 # CUSTOM
		initial_data["write_perm"] = -1 # CUSTOM
		
		var game_obj = obj_handler.create_gameobject_internal(0, "game_instance", initial_data)
		if not game_obj.is_empty():
			game_id = game_obj["key"]
			# Add all players to ACL
			var player_ids_ints = []
			for p_id in players:
				player_ids_ints.append(int(p_id))
			
			obj_handler.add_to_acl(game_id, "read", player_ids_ints)
			obj_handler.add_to_acl(game_id, "write", player_ids_ints)
			print("SERVER: Shared GameInstance created: ", game_id)
	
	_broadcast_to_lobby(lobby_key, "LOBBY_GAME_START", {"game_id": game_id})

func _handle_join_queue(peer_id: int, user_id: int, req_id: String, payload: Dictionary):
	var current_lobby_key = BackendServer.redis_client.hget_value("user:" + str(user_id), "current_lobby_id")
	if not current_lobby_key.is_empty():
		BackendServer.send_response(peer_id, "LOBBY_ERROR", req_id, {"message": "Already in a lobby or queue."})
		return

	var matchmaking_type = payload.get("type", "default_1v1")
	var queue_key = "matchmaking:queue:" + matchmaking_type
	var max_players_for_mode = 2

	# Matchmaking logic
	var available_lobbies = BackendServer.redis_client.zrange_values(queue_key, 0, 0)
	
	var target_lobby_key = ""
	if not available_lobbies.is_empty():
		target_lobby_key = available_lobbies[0]
		print("SERVER: Matchmaking - Found existing lobby ", target_lobby_key, " for user ", user_id)
	else:
		print("SERVER: Matchmaking - No lobby found. Creating new for user ", user_id)
		
		var new_lobby_id = BackendServer.redis_client.increment_value("global:next_lobby_id")
		target_lobby_key = "lobby:" + str(new_lobby_id)
		
		var lobby_data = {
			"id": new_lobby_id,
			"name": "Matchmaking Game #" + str(new_lobby_id),
			"owner_id": - 1, # system
			"max_players": max_players_for_mode,
			"is_private": "1",
			"status": "matching",
			"matchmaking_type": matchmaking_type
		}
		BackendServer.redis_client.hset_multiple_values(target_lobby_key, lobby_data)
		BackendServer.redis_client.zadd_values(queue_key, {target_lobby_key: 0})
		# Make matchmaking lobbies visible in the public list
		BackendServer.redis_client.zadd_values("lobbies:public", {target_lobby_key: 0})

	_join_lobby_logic(peer_id, user_id, req_id, target_lobby_key)
	
	# Auto-set ready status for matchmaking users
	BackendServer.redis_client.sadd_values(target_lobby_key + ":ready_players", [str(user_id)])
	
	var player_count = BackendServer.redis_client.scard_count(target_lobby_key + ":players")
	BackendServer.redis_client.zadd_values(queue_key, {target_lobby_key: player_count})
	
	if player_count >= max_players_for_mode:
		print("SERVER: Matchmaking - Lobby ", target_lobby_key, " is full. Starting game.")
		BackendServer.redis_client.zrem_values(queue_key, [target_lobby_key])
		_handle_start_game(peer_id, -1, req_id, target_lobby_key)

func _handle_leave_queue(peer_id: int, user_id: int, req_id: String, _payload: Dictionary):
	var current_lobby_key = BackendServer.redis_client.hget_value("user:" + str(user_id), "current_lobby_id")
	
	if current_lobby_key.is_empty():
		return

	var lobby_data = BackendServer.redis_client.hget_all_values(current_lobby_key)
	var matchmaking_type = lobby_data.get("matchmaking_type")

	if not matchmaking_type or matchmaking_type.is_empty():
		BackendServer.send_response(peer_id, "LOBBY_ERROR", req_id, {"message": "Not in a matchmaking queue."})
		return
		
	print("SERVER: Matchmaking - User ", user_id, " leaving queue.")
	_handle_leave(peer_id, user_id, req_id, current_lobby_key)

func _handle_client_disconnected(user_id: int):
	var lobby_key = BackendServer.redis_client.hget_value("user:" + str(user_id), "current_lobby_id")
	if lobby_key.is_empty():
		return

	print("SERVER: User ", user_id, " disconnected from lobby ", lobby_key, ". Starting reconnection timer.")
	_broadcast_to_lobby(lobby_key, "LOBBY_PLAYER_DISCONNECTED", {"user_id": user_id})

	var timer = get_tree().create_timer(RECONNECTION_TIMEOUT_SECONDS)
	timer.timeout.connect(func(): _on_reconnection_timeout(user_id, lobby_key))

func _on_reconnection_timeout(user_id: int, lobby_key: String):
	if BackendServer.get_peer_id_from_user_id(user_id) != -1:
		print("SERVER: User ", user_id, " reconnected in time.")
		_broadcast_to_lobby(lobby_key, "LOBBY_PLAYER_RECONNECTED", {"user_id": user_id})
		return

	print("SERVER: Reconnection timeout for user ", user_id, ". Removing from lobby.")
	_handle_leave(-1, user_id, "", lobby_key)
