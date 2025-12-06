extends Control

@export var login_controller: LoginController

# --- Riferimenti ai Nodi della UI ---

# Sezione Registrazione
@onready var register_username_input: LineEdit = $PanelRegister/UserLineEdit
@onready var register_password_input: LineEdit = $PanelRegister/PasswordLineEdit
@onready var register_button: Button = $PanelRegister/RegisterButton
@onready var register_status_label: Label = $PanelRegister/RegisterStatus

# Sezione Login
@onready var login_username_input: LineEdit = $PanelLogin/UserLineEdit
@onready var login_password_input: LineEdit = $PanelLogin/PasswordLineEdit
@onready var login_button: Button = $PanelLogin/LoginButton
@onready var login_status_label: Label = $PanelLogin/LoginStatus

@onready var connection_status_label: Label =  $Label/ConnectionStatus

@onready var connection_button: Button = $Label/ConnectionStatus/Button

func _ready() -> void:
	# Controlla se il LoginController è stato assegnato nell'editor
	if not login_controller:
		printerr("AccessPanel: LoginController (login_controller) non è stato assegnato nell'Inspector!")
		register_status_label.text = "ERRORE: Configurazione mancante."
		login_status_label.text = "ERRORE: Configurazione mancante."
		return
	
	# Connetti i segnali dei pulsanti
	register_button.pressed.connect(_on_register_button_pressed)
	login_button.pressed.connect(_on_login_button_pressed)
	connection_button.pressed.connect(_on_connection_button_pressed)
	
	# Connetti il segnale "Invio" dai campi password per un accesso rapido
	register_password_input.text_submitted.connect(_on_register_button_pressed)
	login_password_input.text_submitted.connect(_on_login_button_pressed)

	# Connetti i segnali dal LoginController per aggiornare la UI
	login_controller.registration_success.connect(_on_registration_success)
	login_controller.registration_failed.connect(_on_registration_failed)
	login_controller.login_success.connect(_on_login_success)
	login_controller.login_failed.connect(_on_login_failed)

	if not NetworkManager.session_token.is_empty():
		NetworkManager.connect_to_server()

# --- Gestori dei segnali dei Pulsanti ---

func _on_register_button_pressed(_extra_arg = null) -> void:
	var username = register_username_input.text
	var password = register_password_input.text
	register_status_label.text = "Registrazione in corso..."
	login_controller.attempt_register(username, password)

func _on_login_button_pressed(_extra_arg = null) -> void:
	var username = login_username_input.text
	var password = login_password_input.text
	login_status_label.text = "Login in corso..."
	login_controller.attempt_login(username, password)

func _on_connection_button_pressed() -> void:
	NetworkManager.connect_to_server()
# --- Gestori dei segnali dal LoginController ---

func _on_registration_success() -> void:
	register_status_label.text = "Registrazione completata con successo!"

func _on_registration_failed(reason: String) -> void:
	register_status_label.text = "Registrazione fallita: " + reason

func _on_login_success(user_data: Dictionary) -> void:
	login_status_label.text = "Login riuscito! Benvenuto, " + user_data.get("username", "utente")
	
	await get_tree().create_timer(2.0).timeout
	get_tree().change_scene_to_file("res://scenes/client/main_menu.tscn")

func _on_login_failed(reason: String) -> void:
	login_status_label.text = "Login fallito: " + reason
	
func _process(_delta):
	if not NetworkManager.ws_connected:
		connection_status_label.text = "Not Connected"
		connection_button.disabled = false
	else:
		if NetworkManager.ws_connecting:
			connection_status_label.text = "Connecting..."
		else:
			connection_status_label.text = "Connected"
		connection_button.disabled = true
