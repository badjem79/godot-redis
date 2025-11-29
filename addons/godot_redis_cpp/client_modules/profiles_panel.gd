extends Control

# Controller per interagire con i profili, da assegnare nell'editor
@export var profile_controller: Node

# Riferimenti ai nodi della UI
@onready var user_id_input: LineEdit = $HBoxContainer/UserIdInput
@onready var get_profiles_button: Button = $HBoxContainer/GetProfilesButton
@onready var profile_list: ItemList = $ScrollContainer/ProfileList
@onready var back_button: Button = $BackButton

# --- Pannello Dettaglio Profilo ---
@onready var detail_panel: PanelContainer = $ProfileDetailPanel
@onready var detail_username_label: Label = $ProfileDetailPanel/MarginContainer/VBox/UsernameLabel
@onready var detail_level_label: Label = $ProfileDetailPanel/MarginContainer/VBox/LevelLabel
@onready var detail_bio_edit: TextEdit = $ProfileDetailPanel/MarginContainer/VBox/BioEdit
@onready var detail_avatar_edit: LineEdit = $ProfileDetailPanel/MarginContainer/VBox/AvatarEdit
@onready var save_button: Button = $ProfileDetailPanel/MarginContainer/VBox/SaveButton
@onready var status_label: Label = $ProfileDetailPanel/MarginContainer/VBox/StatusLabel

# Memorizza i dati dei profili ricevuti per un accesso rapido
var _received_profiles: Dictionary = {}
var _selected_user_id: String = ""

func _ready() -> void:
	# Connessione dei segnali dei bottoni e del controller
	back_button.pressed.connect(_on_back_button_pressed)
	get_profiles_button.pressed.connect(_on_get_profiles_button_pressed)
	profile_list.item_selected.connect(_on_profile_selected)
	save_button.pressed.connect(_on_save_button_pressed)
	
	if profile_controller:
		profile_controller.profiles_received.connect(_on_profiles_received)
		profile_controller.profile_update_success.connect(_on_profile_update_success)
		profile_controller.profile_update_failed.connect(_on_profile_update_failed)
	else:
		printerr("ProfileController non assegnato a ProfilesPanel.")

	# Richiede il profilo dell'utente corrente all'avvio
	if profile_controller and NetworkManager.user_data.has("user_id"):
		profile_controller.get_profiles([NetworkManager.user_data.user_id])
	
	# Nascondi il pannello di dettaglio all'inizio
	detail_panel.hide()


func _on_back_button_pressed() -> void:
	# Torna al menu principale
	get_tree().change_scene_to_file("res://scenes/client/main_menu.tscn")


func _on_get_profiles_button_pressed() -> void:
	var text = user_id_input.text.strip_edges()
	if text.is_empty():
		# Se il campo è vuoto, richiede tutti i profili
		if profile_controller:
			profile_controller.get_all_profiles()
		return

	# Separa gli ID inseriti (es. "user1, user2, user3")
	var user_ids_raw = text.split(",", false) # false per non ignorare spazi vuoti
	# Pulisce gli ID da spazi extra
	var user_ids = []
	for id_str in user_ids_raw:
		if not id_str.strip_edges().is_empty():
			user_ids.append(id_str.strip_edges())
	
	if profile_controller:
		profile_controller.get_profiles(user_ids)


func _on_profiles_received(profiles_data: Dictionary) -> void:
	_received_profiles = profiles_data
	
	# Pulisce la lista prima di aggiungere i nuovi risultati
	profile_list.clear()
		
	# Itera sui profili ricevuti e crea una voce per ciascuno
	for user_id in profiles_data:
		var data = profiles_data[user_id]
		var username = data.get("username", "Sconosciuto")
		# Aggiunge l'username alla lista e l'ID utente come metadata
		profile_list.add_item("%s (ID: %s)" % [username, user_id])
		profile_list.set_item_metadata(profile_list.get_item_count() - 1, user_id)


func _on_profile_selected(index: int):
	_selected_user_id = profile_list.get_item_metadata(index)
	if not _received_profiles.has(_selected_user_id):
		return

	var profile_data = _received_profiles[_selected_user_id]
	var current_user_id = str(NetworkManager.user_data.get("user_id", -1))
	var is_owner = (_selected_user_id == current_user_id)

	# Popola e configura il pannello di dettaglio
	detail_username_label.text = "Username: " + profile_data.get("username", "N/D")
	detail_level_label.text = "Livello: " + str(profile_data.get("level", "N/D"))
	detail_bio_edit.text = profile_data.get("bio", "")
	detail_avatar_edit.text = profile_data.get("avatar_url", "")
	
	# Abilita/disabilita l'editing
	detail_bio_edit.editable = is_owner
	detail_avatar_edit.editable = is_owner
	save_button.visible = is_owner
	status_label.text = ""
	
	detail_panel.show()


func _on_save_button_pressed():
	if _selected_user_id.is_empty():
		return

	var data_to_update = {
		"bio": detail_bio_edit.text,
		"avatar_url": detail_avatar_edit.text
	}
	
	# Aggiungi qui altri campi editabili se necessario
	# Esempio: "display_title": detail_title_edit.text
	
	status_label.text = "Salvataggio in corso..."
	profile_controller.update_profile(data_to_update)


func _on_profile_update_success(updated_fields: Dictionary):
	status_label.text = "Profilo salvato con successo!"
	status_label.modulate = Color.GREEN
	
	# Aggiorna i dati locali per riflettere le modifiche
	if _received_profiles.has(_selected_user_id):
		_received_profiles[_selected_user_id].merge(updated_fields)


func _on_profile_update_failed(reason: String):
	status_label.text = "Errore: " + reason
	status_label.modulate = Color.RED
