extends Control

@export var lobby_controller: Node

# --- Riferimenti UI ---
# Matchmaking
@onready var join_queue_button: Button = $VBoxContainer/MatchmakingBox/JoinQueueButton
@onready var leave_queue_button: Button = $VBoxContainer/MatchmakingBox/LeaveQueueButton
@onready var matchmaking_status_label: Label = $VBoxContainer/MatchmakingBox/MatchmakingStatusLabel

# Lista Lobby
@onready var refresh_button: Button = $VBoxContainer/LobbyListBox/VBoxContainer/HBoxContainer/RefreshButton
@onready var lobby_list: ItemList = %LobbyList

# Creazione Lobby
@onready var lobby_name_input: LineEdit = $VBoxContainer/LobbyListBox/CreateLobbyBox/LobbyNameInput
@onready var create_lobby_button: Button = $VBoxContainer/LobbyListBox/CreateLobbyBox/CreateLobbyButton

# Pannello Lobby Corrente
@onready var current_lobby_panel: PanelContainer = $VBoxContainer/CurrentLobbyPanel
@onready var lobby_title_label: Label = $VBoxContainer/CurrentLobbyPanel/VBoxContainer/LobbyTitleLabel
@onready var player_list: ItemList = %PlayerList
@onready var ready_button: Button = $VBoxContainer/CurrentLobbyPanel/VBoxContainer/HBoxContainer/ReadyButton
@onready var leave_lobby_button: Button = $VBoxContainer/CurrentLobbyPanel/VBoxContainer/HBoxContainer/LeaveLobbyButton
@onready var start_game_button: Button = $VBoxContainer/CurrentLobbyPanel/VBoxContainer/HBoxContainer/StartGameButton

@onready var back_button: Button = $VBoxContainer/MatchmakingBox/BackButton

var _current_lobby_data: Dictionary = {}
var _current_players: Array = []

func _ready() -> void:
	if not lobby_controller:
		printerr("LobbyPanel: lobby_controller non assegnato!")
		return

	# Connessione segnali UI
	back_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/client/main_menu.tscn"))
	refresh_button.pressed.connect(lobby_controller.request_lobby_list)
	create_lobby_button.pressed.connect(_on_create_lobby_pressed)
	join_queue_button.pressed.connect(_on_join_queue_pressed)
	leave_queue_button.pressed.connect(lobby_controller.leave_matchmaking_queue)
	leave_lobby_button.pressed.connect(lobby_controller.leave_lobby)
	ready_button.pressed.connect(_on_ready_button_pressed)
	start_game_button.pressed.connect(lobby_controller.start_game)
	lobby_list.item_activated.connect(_on_lobby_selected)

	# Connessione segnali dal controller
	lobby_controller.lobby_list_updated.connect(_on_lobby_list_updated)
	lobby_controller.joined_lobby.connect(_on_joined_lobby)
	lobby_controller.left_lobby.connect(_on_left_lobby)
	lobby_controller.player_joined_lobby.connect(_on_player_joined_lobby)
	lobby_controller.player_left_lobby.connect(_on_player_left_lobby)
	lobby_controller.player_ready_status_changed.connect(_on_player_ready_status_changed)
	lobby_controller.game_started.connect(_on_game_started)
	lobby_controller.operation_failed.connect(_on_operation_failed)

	# Stato iniziale UI
	current_lobby_panel.hide()
	leave_queue_button.hide()
	
	# Richiedi la lista delle lobby all'avvio
	lobby_controller.request_lobby_list()


func _update_lobby_view():
	"""Aggiorna la UI della lobby corrente con i dati più recenti."""
	if _current_lobby_data.is_empty():
		current_lobby_panel.hide()
		return

	lobby_title_label.text = "Lobby: %s" % _current_lobby_data.get("name", "N/D")
	
	player_list.clear()
	for player_id in _current_players:
		# Qui potremmo voler recuperare i nomi utente, per ora usiamo gli ID
		# In un'implementazione più avanzata, si potrebbe avere una cache di profili
		player_list.add_item("Giocatore %s" % player_id)

	var is_owner = str(NetworkManager.user_data.get("id")) == str(_current_lobby_data.get("owner_id"))
	start_game_button.visible = is_owner
	
	current_lobby_panel.show()


# --- Gestori Segnali dal Controller ---

func _on_lobby_list_updated(lobbies: Array) -> void:
	lobby_list.clear()
	for lobby_data in lobbies:
		var item_text = "%s (%s/%s)" % [
			lobby_data.get("name", "Senza nome"),
			lobby_data.get("player_count", 0),
			lobby_data.get("max_players", 2)
		]
		lobby_list.add_item(item_text)
		lobby_list.set_item_metadata(lobby_list.get_item_count() - 1, lobby_data.get("id"))

func _on_joined_lobby(lobby_data: Dictionary, players: Array) -> void:
	_current_lobby_data = lobby_data
	_current_players = players
	
	# Se siamo entrati in una lobby di matchmaking, aggiorniamo la UI del matchmaking
	if lobby_data.get("matchmaking_type"):
		matchmaking_status_label.text = "In coda... In attesa di altri giocatori."
		join_queue_button.hide()
		leave_queue_button.show()
	else:
		matchmaking_status_label.text = ""
		join_queue_button.show()
		leave_queue_button.hide()

	_update_lobby_view()

func _on_left_lobby() -> void:
	_current_lobby_data.clear()
	_current_players.clear()
	
	current_lobby_panel.hide()
	matchmaking_status_label.text = "Hai lasciato la coda."
	join_queue_button.show()
	leave_queue_button.hide()
	ready_button.button_pressed = false
	
	# Aggiorna la lista delle lobby pubbliche
	lobby_controller.request_lobby_list()

func _on_player_joined_lobby(user_id: String) -> void:
	if not user_id in _current_players:
		_current_players.append(user_id)
		_update_lobby_view()

func _on_player_left_lobby(user_id: String) -> void:
	if user_id in _current_players:
		_current_players.erase(user_id)
		_update_lobby_view()

func _on_player_ready_status_changed(user_id: String, is_ready: bool) -> void:
	# Trova l'item nella lista e aggiorna il suo stato (es. colore o testo)
	for i in range(player_list.item_count):
		# Questa logica assume che l'ID sia nel testo.
		# Una soluzione migliore sarebbe usare i metadati per ogni giocatore.
		if player_list.get_item_text(i).ends_with(user_id):
			var ready_str = "[PRONTO]" if is_ready else ""
			player_list.set_item_text(i, "Giocatore %s %s" % [user_id, ready_str])
			break

func _on_game_started(game_info: Dictionary) -> void:
	matchmaking_status_label.text = "Partita trovata! Inizio..."
	print("PARTITA AVVIATA: ", game_info)
	# Qui si cambierebbe scena per entrare nella partita vera e propria
	# get_tree().change_scene_to_file("res://scenes/game.tscn")

func _on_operation_failed(reason: String) -> void:
	matchmaking_status_label.text = "Errore: %s" % reason
	# Potresti voler nascondere questo messaggio dopo qualche secondo


# --- Gestori Segnali UI ---

func _on_create_lobby_pressed() -> void:
	var lobby_name = lobby_name_input.text
	if lobby_name.is_empty():
		lobby_name = "Partita di %s" % NetworkManager.user_data.get("username", "Utente")
	
	# Per ora creiamo lobby pubbliche da 2 giocatori
	lobby_controller.create_lobby(lobby_name, 2, false)

func _on_join_queue_pressed() -> void:
	matchmaking_status_label.text = "Ricerca di una partita in corso..."
	join_queue_button.hide()
	leave_queue_button.show()
	lobby_controller.join_matchmaking_queue("default_1v1")

func _on_lobby_selected() -> void:
	var selected_id = lobby_list.get_item_metadata(lobby_list.get_selected_items()[0])
	if selected_id:
		lobby_controller.join_lobby(str(selected_id))

func _on_ready_button_pressed() -> void:
	# Il bottone è in modalità toggle
	lobby_controller.set_ready_status(ready_button.button_pressed)
