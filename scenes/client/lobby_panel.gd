# lobby_panel.gd
# Main UI controller for the lobby system.
extends Control

@export var lobby_controller: Node

# --- UI References ---
# Matchmaking
@onready var join_queue_button: Button = $VBoxContainer/MatchmakingBox/JoinQueueButton
@onready var leave_queue_button: Button = $VBoxContainer/MatchmakingBox/LeaveQueueButton
@onready var matchmaking_status_label: Label = $VBoxContainer/MatchmakingBox/MatchmakingStatusLabel
@onready var back_button: Button = $VBoxContainer/MatchmakingBox/BackButton

# Lobby List
@onready var refresh_button: Button = $VBoxContainer/LobbyListBox/VBoxContainer/HBoxContainer/RefreshButton
@onready var lobby_list_ui: ItemList = %LobbyList

# Lobby Creation
@onready var lobby_name_input: LineEdit = $VBoxContainer/LobbyListBox/CreateLobbyBox/LobbyNameInput
@onready var create_lobby_button: Button = $VBoxContainer/LobbyListBox/CreateLobbyBox/CreateLobbyButton

# Current Lobby Panel
@onready var current_lobby_panel: PanelContainer = $VBoxContainer/CurrentLobbyPanel
@onready var lobby_title_label: Label = $VBoxContainer/CurrentLobbyPanel/VBoxContainer/LobbyTitleLabel
@onready var player_list_ui: ItemList = %PlayerList
@onready var ready_button: Button = $VBoxContainer/CurrentLobbyPanel/VBoxContainer/HBoxContainer/ReadyButton
@onready var join_leave_button: Button = $VBoxContainer/CurrentLobbyPanel/VBoxContainer/HBoxContainer/JoinLeaveButton
@onready var start_game_button: Button = $VBoxContainer/CurrentLobbyPanel/VBoxContainer/HBoxContainer/StartGameButton

# --- State ---
var _current_lobby_data: Dictionary = {}
var _current_players: Dictionary = {} # user_id (int) -> { "username": String, "is_ready": bool }
var _selected_lobby_data: Dictionary = {}
var _user_lobby_id: String = ""

func _ready() -> void:
	if not lobby_controller:
		printerr("LobbyPanel: lobby_controller not assigned!")
		return

	# UI Signal Connections
	back_button.pressed.connect(_on_back_button_pressed)
	refresh_button.pressed.connect(lobby_controller.request_lobby_list)
	create_lobby_button.pressed.connect(_on_create_lobby_pressed)
	join_queue_button.pressed.connect(_on_join_queue_pressed)
	leave_queue_button.pressed.connect(lobby_controller.leave_matchmaking_queue)
	join_leave_button.pressed.connect(_on_join_leave_button_pressed)
	ready_button.pressed.connect(_on_ready_button_pressed)
	start_game_button.pressed.connect(lobby_controller.start_game)
	lobby_list_ui.item_selected.connect(_on_lobby_selected)

	# Controller Signal Connections
	lobby_controller.lobby_list_updated.connect(_on_lobby_list_updated)
	lobby_controller.joined_lobby.connect(_on_joined_lobby)
	lobby_controller.left_lobby.connect(_on_left_lobby)
	lobby_controller.player_joined_lobby.connect(_on_player_joined_lobby)
	lobby_controller.player_left_lobby.connect(_on_player_left_lobby)
	lobby_controller.player_ready_status_changed.connect(_on_player_ready_status_changed)
	lobby_controller.lobby_owner_changed.connect(_on_owner_changed)
	lobby_controller.game_started.connect(_on_game_started)
	lobby_controller.operation_failed.connect(_on_operation_failed)

	# Initial UI State
	current_lobby_panel.hide()
	leave_queue_button.hide()
	
	# Check if user is already in a lobby (persistence check)
	var user_current_lobby_id = NetworkManager.user_data.get("current_lobby_id")
	if user_current_lobby_id and not user_current_lobby_id.is_empty():
		var parts = user_current_lobby_id.split(":")
		if parts.size() > 1:
			_user_lobby_id = parts[1]

	# Initial lobby list request
	lobby_controller.request_lobby_list()

func _set_ui_state(in_lobby: bool):
	"""Toggles UI interactivity based on lobby membership."""
	join_queue_button.disabled = in_lobby
	create_lobby_button.disabled = in_lobby
	# Disable selection if already in a lobby to focus on current one
	lobby_list_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE if in_lobby else Control.MOUSE_FILTER_STOP
	
	if in_lobby:
		matchmaking_status_label.text = "You are in a lobby. Leave to join another."

func _refresh_lobby_ui():
	"""Updates the visible details of the active or selected lobby."""
	var data = _current_lobby_data if not _current_lobby_data.is_empty() else _selected_lobby_data
	var players = _current_players if not _current_lobby_data.is_empty() else {}
	
	# Special case: showing details for a selected lobby before joining
	if players.is_empty() and data.has("players"):
		for p in data.get("players", []):
			players[int(p["id"])] = {"username": p["username"], "is_ready": false}

	if data.is_empty():
		current_lobby_panel.hide()
		return

	var lobby_id = data.get("id", "N/A")
	lobby_title_label.text = "Lobby: %s (ID: %s)" % [data.get("name", "N/A"), str(lobby_id)]
	
	player_list_ui.clear()
	for p_id in players:
		var p_info = players[p_id]
		var ready_str = " [READY]" if p_info.get("is_ready") else ""
		player_list_ui.add_item("%s%s" % [p_info.get("username", "Unknown"), ready_str])

	var is_member = not _current_lobby_data.is_empty() and str(_current_lobby_data.get("id")) == str(data.get("id"))
	
	if is_member:
		join_leave_button.text = "Leave Lobby"
		join_leave_button.disabled = false
		ready_button.show()
		var is_owner = str(NetworkManager.user_data.get("id")) == str(data.get("owner_id"))
		start_game_button.visible = is_owner
	else:
		var is_matching = data.get("status") == "matching"
		join_leave_button.text = "In Matchmaking" if is_matching else "Join Lobby"
		join_leave_button.disabled = is_matching
		ready_button.hide()
		start_game_button.hide()

	current_lobby_panel.show()

# --- Signal Handlers (Controller) ---

func _on_lobby_list_updated(lobbies: Array) -> void:
	lobby_list_ui.clear()
	_selected_lobby_data = {}
	
	# Only hide current panel if not active in a lobby
	if _current_lobby_data.is_empty():
		current_lobby_panel.hide()
	
	for lobby in lobbies:
		var txt = "%s (%d/%d)" % [lobby.get("name", "Unnamed"), int(lobby.get("player_count", 0)), int(lobby.get("max_players", 2))]
		lobby_list_ui.add_item(txt)
		lobby_list_ui.set_item_metadata(lobby_list_ui.get_item_count() - 1, lobby)
		
		# Auto-select if it's the lobby we are currently in
		if str(lobby.get("id")) == _user_lobby_id:
			lobby_list_ui.select(lobby_list_ui.get_item_count() - 1)
			_current_lobby_data = lobby
			# Re-populate local cache with full player info from the list update
			_current_players.clear()
			for p in lobby.get("players", []):
				_current_players[int(p["id"])] = {"username": p["username"], "is_ready": false}
			_refresh_lobby_ui()

func _on_joined_lobby(lobby_data: Dictionary, players: Array) -> void:
	if lobby_data.is_empty():
		printerr("LobbyPanel: Received empty lobby_data on join!")
		return
		
	_current_lobby_data = lobby_data
	_current_players.clear()
	for p in players:
		_current_players[int(p.get("id"))] = {"username": p.get("username", "Unknown"), "is_ready": false}
	
	_user_lobby_id = str(lobby_data.get("id"))
	
	if lobby_data.get("matchmaking_type"):
		matchmaking_status_label.text = "Queued... Waiting for players."
		join_queue_button.hide()
		leave_queue_button.show()
	else:
		matchmaking_status_label.text = ""
		join_queue_button.show()
		leave_queue_button.hide()
	
	_set_ui_state(true)
	_refresh_lobby_ui()

func _on_left_lobby() -> void:
	_current_lobby_data.clear()
	_current_players.clear()
	_user_lobby_id = ""
	
	current_lobby_panel.hide()
	matchmaking_status_label.text = "Left lobby."
	join_queue_button.show()
	leave_queue_button.hide()
	ready_button.button_pressed = false
	_set_ui_state(false)
	lobby_controller.request_lobby_list()

func _on_player_joined_lobby(user_id: int, username: String) -> void:
	if not _current_players.has(user_id):
		_current_players[user_id] = {"username": username, "is_ready": false}
		_refresh_lobby_ui()

func _on_player_left_lobby(user_id: int) -> void:
	if _current_players.has(user_id):
		_current_players.erase(user_id)
		_refresh_lobby_ui()

func _on_player_ready_status_changed(user_id: int, is_ready: bool) -> void:
	if _current_players.has(user_id):
		_current_players[user_id]["is_ready"] = is_ready
		_refresh_lobby_ui()

func _on_owner_changed(new_owner_id: int):
	_current_lobby_data["owner_id"] = new_owner_id
	_refresh_lobby_ui()

func _on_game_started(game_info: Dictionary) -> void:
	var game_id = game_info.get("game_id", "N/A")
	matchmaking_status_label.text = "MATCH FOUND! Session: %s" % game_id
	print("Lobby: Game starting with shared object: ", game_id)
	
	# Clear lobby state as we are now "in-game"
	# In a full game, you would load the game scene here:
	# get_tree().change_scene_to_file("res://scenes/client/game_world.tscn")
	
	# For this demo, we'll just disable the lobby UI to simulate the transition
	current_lobby_panel.modulate = Color(0.7, 1.0, 0.7) # Highlight green
	start_game_button.disabled = true
	ready_button.disabled = true
	join_leave_button.disabled = true

func _on_operation_failed(reason: String) -> void:
	matchmaking_status_label.text = "Error: %s" % reason

# --- Signal Handlers (UI) ---

func _on_back_button_pressed() -> void:
	if not _current_lobby_data.is_empty():
		lobby_controller.leave_lobby()
	elif leave_queue_button.visible:
		lobby_controller.leave_matchmaking_queue()
	get_tree().change_scene_to_file("res://scenes/client/main_menu.tscn")

func _on_create_lobby_pressed() -> void:
	var lobby_name = lobby_name_input.text
	if lobby_name.is_empty():
		lobby_name = "%s's Match" % NetworkManager.user_data.get("username", "Player")
	lobby_controller.create_lobby(lobby_name, 2, false)

func _on_join_queue_pressed() -> void:
	matchmaking_status_label.text = "Searching for match..."
	join_queue_button.hide()
	leave_queue_button.show()
	lobby_controller.join_matchmaking_queue("default_1v1")
	_set_ui_state(true)

func _on_lobby_selected(index: int) -> void:
	_selected_lobby_data = lobby_list_ui.get_item_metadata(index)
	_refresh_lobby_ui()

func _on_join_leave_button_pressed() -> void:
	if not _current_lobby_data.is_empty():
		lobby_controller.leave_lobby()
	elif not _selected_lobby_data.is_empty():
		lobby_controller.join_lobby(str(_selected_lobby_data.id))

func _on_ready_button_pressed() -> void:
	lobby_controller.set_ready_status(ready_button.button_pressed)
