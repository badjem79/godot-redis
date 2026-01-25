# LobbyController.gd
# Handles client-side lobby communication and state management.
extends Node

signal lobby_list_updated(lobbies)
signal joined_lobby(lobby_data, players)
signal left_lobby
signal player_joined_lobby(user_id, username)
signal player_left_lobby(user_id)
signal player_ready_status_changed(user_id, is_ready)
signal lobby_owner_changed(new_owner_id)
signal game_started(game_info)
signal operation_failed(reason)

var _registered_handlers = [
	"LOBBY_LIST_UPDATE",
	"LOBBY_JOIN_SUCCESS",
	"LOBBY_LEAVE_SUCCESS",
	"LOBBY_PLAYER_JOINED",
	"LOBBY_PLAYER_LEFT",
	"LOBBY_PLAYER_READY",
	"LOBBY_OWNER_CHANGED",
	"LOBBY_GAME_START",
	"LOBBY_ERROR"
]

func _ready():
	for msg_type in _registered_handlers:
		# Dynamically bind handlers, e.g. "LOBBY_LIST_UPDATE" -> "_on_lobby_list_update"
		NetworkManager.register_handler(msg_type, Callable(self, "_on_" + msg_type.to_lower()))

func _exit_tree():
	for msg_type in _registered_handlers:
		NetworkManager.unregister_handler(msg_type)

# --- Public API ---

func request_lobby_list():
	NetworkManager.send_message("LOBBY_GET_LIST", {}, _on_lobby_list_update)

func create_lobby(name: String, max_players: int, is_private: bool):
	var payload = {"name": name, "max_players": max_players, "private": is_private}
	NetworkManager.send_message("LOBBY_CREATE", payload, _on_lobby_join_success)

func join_lobby(lobby_id: String):
	NetworkManager.send_message("LOBBY_JOIN", {"id": lobby_id}, _on_lobby_join_success)

func leave_lobby():
	NetworkManager.send_message("LOBBY_LEAVE", {})

func set_ready_status(is_ready: bool):
	NetworkManager.send_message("LOBBY_SET_READY", {"ready": is_ready})

func start_game():
	NetworkManager.send_message("LOBBY_START_GAME", {})

func join_matchmaking_queue(matchmaking_type: String):
	"""Requests to join a specific matchmaking queue."""
	NetworkManager.send_message("MATCHMAKING_JOIN_QUEUE", {"type": matchmaking_type})

func leave_matchmaking_queue():
	"""Requests to leave the current matchmaking queue."""
	NetworkManager.send_message("MATCHMAKING_LEAVE_QUEUE", {})

# --- Server Response Handlers ---

func _on_lobby_list_update(payload):
	emit_signal("lobby_list_updated", payload.get("lobbies", []))

func _on_lobby_join_success(payload):
	emit_signal("joined_lobby", payload.get("lobby_data", {}), payload.get("players", []))

func _on_lobby_leave_success(_payload):
	emit_signal("left_lobby")

func _on_lobby_player_joined(payload):
	emit_signal("player_joined_lobby", int(payload.get("user_id")), payload.get("username", "Player"))

func _on_lobby_player_left(payload):
	emit_signal("player_left_lobby", int(payload.get("user_id")))
	
func _on_lobby_player_ready(payload):
	emit_signal("player_ready_status_changed", int(payload.get("user_id")), payload.get("is_ready"))

func _on_lobby_owner_changed(payload):
	emit_signal("lobby_owner_changed", int(payload.get("new_owner_id")))
	
func _on_lobby_game_start(payload):
	emit_signal("game_started", payload)

func _on_lobby_error(payload):
	emit_signal("operation_failed", payload.get("message", "Unknown error"))
