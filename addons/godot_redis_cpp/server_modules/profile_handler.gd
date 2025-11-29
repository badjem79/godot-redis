# ProfileHandler.gd
extends Node

@export_category("Profile Fields")
# --- Lista dei campi del profilo che il client è autorizzato a modificare ---
@export var allowed_profile_fields = [
	"avatar_url",
	"bio",
	"display_title",
	"preferred_language"
]

@export_category("Profile Visibility")

# Campi visibili a tutti (profilo pubblico)
# Configurabili dall'Inspector di Godot.
@export var public_profile_fields: Array[String] = [
	"id",
	"username",
	"level",
	"avatar_url",
	"bio",
	"display_title"
]

# Campi aggiuntivi visibili solo al proprietario del profilo.
# La vista privata includerà TUTTI i campi pubblici PIÙ questi.
@export var private_profile_fields: Array[String] = [
	"gold",
	"created_at",
	"preferred_language"
]

# Lista di campi protetti che NON possono MAI essere modificati da un client.
# Questa lista è interna e non esportata per sicurezza.
const PROTECTED_FIELDS = ["id", "username", "password_hash", "created_at", "level", "gold"]

func _ready():
	# Registra questo gestore con il server autoload
	BackendServer.register_handler(self)
	
func _exit_tree():
	BackendServer.unregister_handler(self)

# Questo metodo è il "contratto" per la registrazione automatica
func get_handled_message_types() -> Array[String]:
	return ["PROFILE_UPDATE", "ACHIEVEMENT_UNLOCK", "GET_PROFILES"]

# Metodo principale chiamato dal dispatcher del server
func handle_message(peer_id: int, msg_type: String, req_id: String, payload: Dictionary, token: String):
	# Tutti i messaggi gestiti da questo handler richiedono autenticazione.
	# Il server principale ha già verificato il token e l'autenticazione.
	match msg_type:
		"PROFILE_UPDATE":
			_handle_profile_update(peer_id, req_id, payload)
		"ACHIEVEMENT_UNLOCK":
			_handle_achievement_unlock(peer_id, req_id, payload)
		"GET_PROFILES":
			_handle_get_profiles(peer_id, req_id, payload)

# --- Gestori di Logica Interni ---
func _handle_get_profiles(peer_id: int, req_id: String, payload: Dictionary):
	var requester_user_id = BackendServer.authenticated_peers[peer_id].user_id
	var ids_to_fetch = payload.get("ids", [])
	
	if ids_to_fetch.is_empty():
		ids_to_fetch = BackendServer.redis_client.smembers_keys("user")

	var profiles_data = {}
	
	# Uniamo i campi privati e pubblici per la vista completa del proprietario.
	# Lo facciamo una volta sola per efficienza.
	var full_private_view_fields = public_profile_fields + private_profile_fields

	for user_id in ids_to_fetch:
		var id = int(user_id)
		var user_key = "user:" + str(id)
		var full_profile = BackendServer.redis_client.hget_all_values(user_key)
		
		if not full_profile.is_empty():
			var filtered_profile
			if id == requester_user_id:
				# Vista privata per il proprietario
				filtered_profile = _filter_profile(full_profile, full_private_view_fields)
			else:
				# Vista pubblica per gli altri
				filtered_profile = _filter_profile(full_profile, public_profile_fields)
			
			profiles_data[id] = filtered_profile

	BackendServer.send_response(peer_id, "GET_PROFILES_RESULT", req_id, {"success": true, "profiles": profiles_data})

func _filter_profile(full_profile: Dictionary, allowed_fields: Array) -> Dictionary:
	var filtered_dict = {}
	for field in allowed_fields:
		if full_profile.has(field):
			filtered_dict[field] = full_profile[field]
	return filtered_dict

func _handle_profile_update(peer_id: int, req_id: String, payload: Dictionary):
	var user_id = BackendServer.authenticated_peers[peer_id].user_id
	var user_key = "user:" + str(user_id)
	
	var fields_to_update = {}
	var invalid_fields = []

	# --- Logica di Sicurezza: Filtra i campi ---
	for field in payload.keys():
		if _validate_profile_field(user_id, field, payload[field]):
			# Il campo è permesso, lo aggiungiamo all'aggiornamento
			fields_to_update[field] = payload[field]
		else:
			# Il campo non è permesso, lo ignoriamo e lo segnaliamo
			invalid_fields.append(field)
	
	if not invalid_fields.is_empty():
		print("SERVER: Peer ", peer_id, " ha tentato di modificare campi non permessi: ", invalid_fields)
		BackendServer.send_response(peer_id, "PROFILE_UPDATE_RESULT", req_id, {
			"success": false,
			"message": "Tentativo di modificare campi non permessi."
		})
		return

	if fields_to_update.is_empty():
		# Nessun campo valido da aggiornare
		BackendServer.send_response(peer_id, "PROFILE_UPDATE_RESULT", req_id, {
			"success": false,
			"message": "Nessun campo valido fornito per l'aggiornamento."
		})
		return

	# Aggiorna i campi in Redis
	var success = BackendServer.redis_client.hset_multiple_values(user_key, fields_to_update)
	
	if success:
		BackendServer.send_response(peer_id, "PROFILE_UPDATE_RESULT", req_id, {
			"success": true,
			"updated_fields": fields_to_update
		})
	else:
		BackendServer.send_response(peer_id, "PROFILE_UPDATE_RESULT", req_id, {
			"success": false,
			"message": "Errore durante il salvataggio dei dati."
		})


func _handle_achievement_unlock(peer_id: int, req_id: String, payload: Dictionary):
	var user_id = BackendServer.authenticated_peers[peer_id].user_id
	var achievement_id = payload.get("id", "")
	
	if achievement_id.is_empty():
		BackendServer.send_response(peer_id, "ACHIEVEMENT_UNLOCKED_RESULT", req_id, {
			"success": false,
			"message": "ID achievement non valido."
		})
		return

	# --- Logica di Validazione del Server ---
	if not _can_unlock_achievement(user_id, achievement_id):
		BackendServer.send_response(peer_id, "ACHIEVEMENT_UNLOCKED_RESULT", req_id, {
			"success": false,
			"message": "Requisiti non soddisfatti."
		})
		return

	var achievements_key = "achievements:" + str(user_id)
	
	# Aggiungi l'achievement al SET dell'utente
	var success = BackendServer.redis_client.sadd_values(achievements_key, [achievement_id])
	
	if success:
		# Potremmo voler controllare se l'elemento è stato effettivamente aggiunto
		# (SADD restituisce il numero di elementi aggiunti).
		# Se il giocatore lo aveva già, non è un errore.
		BackendServer.send_response(peer_id, "ACHIEVEMENT_UNLOCKED_RESULT", req_id, {
			"success": true,
			"id": achievement_id
		})
	else:
		BackendServer.send_response(peer_id, "ACHIEVEMENT_UNLOCKED_RESULT", req_id, {
			"success": false,
			"message": "Errore durante il salvataggio dell'achievement."
		})

# --- FUNZIONI DI VALIDAZIONE (si possono sovrascrivere) ---

func _validate_profile_field(user_id: int, field_name: String, value: Variant) -> bool:
	"""
	Funzione di validazione per un singolo campo del profilo.
	Sovrascrivi questa funzione in una classe figlia per aggiungere logica specifica.
	Restituisce 'true' se il valore è valido, altrimenti 'false'.
	
	Esempio: Controllare che la bio non superi i 200 caratteri.
	"""
	if field_name in allowed_profile_fields and not (field_name in PROTECTED_FIELDS):
		# L'implementazione base accetta tutto, purché il campo sia nella lista.
		return true
	return false


func _can_unlock_achievement(user_id: int, achievement_id: String) -> bool:
	"""
	Funzione di validazione per lo sblocco di un achievement.
	Sovrascrivi questa funzione in una classe figlia per definire i requisiti
	di ogni achievement.
	Restituisce 'true' se l'utente può sbloccarlo, altrimenti 'false'.
	"""
	# L'implementazione base non permette di sbloccare nessun achievement
	# forzando lo sviluppatore a implementare la logica specifica.
	print("AVVISO: La logica per l'achievement '%s' non è implementata." % achievement_id)
	return false
