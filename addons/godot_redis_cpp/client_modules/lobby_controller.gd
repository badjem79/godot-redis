# LobbyController.gd
extends Node

signal lobby_list_updated(lobbies)
signal joined_lobby(lobby_data, players)
signal left_lobby
signal player_joined_lobby(user_id)
signal player_left_lobby(user_id)
signal player_ready_status_changed(user_id, is_ready)
signal game_started(game_info)
signal operation_failed(reason)

var _registered_handlers = [
	"LOBBY_LIST_UPDATE",
	"LOBBY_JOIN_SUCCESS",
	"LOBBY_LEAVE_SUCCESS",
	"LOBBY_PLAYER_JOINED",
	"LOBBY_PLAYER_LEFT",
	"LOBBY_PLAYER_READY",
	"LOBBY_GAME_START",
	"LOBBY_ERROR"
]

func _ready():
	for msg_type in _registered_handlers:
		# Costruisce dinamicamente il nome della funzione, es. "LOBBY_LIST_UPDATE" -> "_on_lobby_list_update"
		NetworkManager.register_handler(msg_type, Callable(self, "_on_" + msg_type.to_lower()))

func _exit_tree():
	for msg_type in _registered_handlers:
		NetworkManager.unregister_handler(msg_type)


# --- API Pubblica del Controller ---

func request_lobby_list():
	NetworkManager.send_message("LOBBY_GET_LIST", {})

func create_lobby(name: String, max_players: int, is_private: bool):
	var payload = {"name": name, "max_players": max_players, "private": is_private}
	NetworkManager.send_message("LOBBY_CREATE", payload)

func join_lobby(lobby_id: String):
	NetworkManager.send_message("LOBBY_JOIN", {"id": lobby_id})

func leave_lobby():
	NetworkManager.send_message("LOBBY_LEAVE", {})

func set_ready_status(is_ready: bool):
	NetworkManager.send_message("LOBBY_SET_READY", {"ready": is_ready})

func start_game():
	NetworkManager.send_message("LOBBY_START_GAME", {})


# --- Gestori delle Risposte dal Server ---

func _on_lobby_list_update(payload):
	emit_signal("lobby_list_updated", payload.get("lobbies", []))

func _on_lobby_join_success(payload):
	emit_signal("joined_lobby", payload.get("lobby_data", {}), payload.get("players", []))

func _on_lobby_leave_success(_payload):
	emit_signal("left_lobby")

func _on_lobby_player_joined(payload):
	emit_signal("player_joined_lobby", payload.get("user_id"))

func _on_lobby_player_left(payload):
	emit_signal("player_left_lobby", payload.get("user_id"))
	
func _on_lobby_player_ready(payload):
	emit_signal("player_ready_status_changed", payload.get("user_id"), payload.get("is_ready"))
	
func _on_lobby_game_started(payload):
	emit_signal("game_started", payload)

func _on_lobby_error(payload):
	emit_signal("operation_failed", payload.get("message", "Errore sconosciuto"))
