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

@onready var network_manager = get_parent()

func register_self_with_network_manager():
    network_manager.register_handler("LOBBY_LIST_UPDATE", Callable(self, "_on_lobby_list_update"))
    network_manager.register_handler("LOBBY_JOIN_SUCCESS", Callable(self, "_on_lobby_join_success"))
    network_manager.register_handler("LOBBY_LEAVE_SUCCESS", Callable(self, "_on_lobby_leave_success"))
    network_manager.register_handler("LOBBY_PLAYER_JOINED", Callable(self, "_on_player_joined"))
    network_manager.register_handler("LOBBY_PLAYER_LEFT", Callable(self, "_on_player_left"))
    network_manager.register_handler("LOBBY_PLAYER_READY", Callable(self, "_on_player_ready"))
    network_manager.register_handler("LOBBY_GAME_START", Callable(self, "_on_game_started"))
    network_manager.register_handler("LOBBY_ERROR", Callable(self, "_on_error"))

# --- API Pubblica del Controller ---

func request_lobby_list():
    network_manager.send_message("LOBBY_GET_LIST", {})

func create_lobby(name: String, max_players: int, is_private: bool):
    var payload = {"name": name, "max_players": max_players, "private": is_private}
    network_manager.send_message("LOBBY_CREATE", payload)

func join_lobby(lobby_id: String):
    network_manager.send_message("LOBBY_JOIN", {"id": lobby_id})

func leave_lobby():
    network_manager.send_message("LOBBY_LEAVE", {})

func set_ready_status(is_ready: bool):
    network_manager.send_message("LOBBY_SET_READY", {"ready": is_ready})

func start_game():
    network_manager.send_message("LOBBY_START_GAME", {})


# --- Gestori delle Risposte dal Server ---

func _on_lobby_list_update(payload):
    emit_signal("lobby_list_updated", payload.get("lobbies", []))

func _on_lobby_join_success(payload):
    emit_signal("joined_lobby", payload.get("lobby_data", {}), payload.get("players", []))

func _on_lobby_leave_success(_payload):
    emit_signal("left_lobby")

func _on_player_joined(payload):
    emit_signal("player_joined_lobby", payload.get("user_id"))

func _on_player_left(payload):
    emit_signal("player_left_lobby", payload.get("user_id"))
    
func _on_player_ready(payload):
    emit_signal("player_ready_status_changed", payload.get("user_id"), payload.get("is_ready"))
    
func _on_game_started(payload):
    emit_signal("game_started", payload)

func _on_error(payload):
    emit_signal("operation_failed", payload.get("message", "Errore sconosciuto"))