extends GridContainer

@export var login_controller: LoginController

@onready var profiles_button: Button = $Profiles
@onready var game_objects_button: Button = $GameObjects
@onready var lobby_button: Button = $Lobby
@onready var logout_button: Button = $Logout

@onready var user_name_label: Label = $"../UserLabel/UserName"

func _ready() -> void:
	profiles_button.pressed.connect(_on_profiles_pressed)
	game_objects_button.pressed.connect(_on_game_objects_pressed)
	lobby_button.pressed.connect(_on_lobby_pressed)
	logout_button.pressed.connect(_on_logout_pressed)
	
	login_controller.logout_success.connect(_go_to_login_scene)
	
	user_name_label.text = NetworkManager.user_data.username
	
func _go_to_login_scene():
	get_tree().change_scene_to_file("res://scenes/client/game_client.tscn")
	
func _on_logout_pressed() -> void:
	login_controller.attempt_logout()
func _on_profiles_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/client/profiles_panel.tscn")
func _on_game_objects_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/client/game_objects_panel.tscn")
func _on_lobby_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/client/lobby_panel.tscn")
