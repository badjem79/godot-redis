# ProfileController.gd
extends Node

# Segnali per notificare l'UI o altre parti del gioco
signal profile_update_success(updated_fields)
signal profile_update_failed(reason)
signal achievement_unlocked_success(achievement_id)
signal achievement_unlocked_failed(reason)
signal profiles_received(profiles_data)

# --- API Pubblica di questo Modulo ---

func update_profile(data: Dictionary):
	"""
	Richiede di aggiornare uno o più campi del profilo utente.
	Esempio: update_profile({"avatar_url": "new_url", "bio": "La mia nuova bio"})
	"""
	if data.is_empty():
		print("ProfileController: nessun dato da aggiornare.")
		return
	
	NetworkManager.send_message("PROFILE_UPDATE", data, _on_profile_update_result)

func unlock_achievement(achievement_id: String):
	"""
	Notifica al server che il giocatore crede di aver sbloccato un achievement.
	Il server verificherà e confermerà.
	"""
	if achievement_id.is_empty():
		return
	
	NetworkManager.send_message("ACHIEVEMENT_UNLOCK", {"id": achievement_id}, _on_achievement_unlocked_result)

func get_profiles(user_ids: Array):
	"""Richiede i dati del profilo per uno o più user_id."""
	if user_ids.is_empty():
		return
	
	NetworkManager.send_message("GET_PROFILES", {"ids": user_ids}, _on_get_profiles_result)

func get_profile_by_name(user_name: String):
	"""Richiede i dati del profilo per uno o più user_id."""
	if user_name.is_empty():
		return
	
	NetworkManager.send_message("GET_PROFILES", {"username": user_name}, _on_get_profiles_result)

func get_all_profiles():
	"""Richiede i dati del profilo per tutti gli utenti."""
	# Invia un payload vuoto. Il server lo interpreterà come una richiesta per tutti.
	NetworkManager.send_message("GET_PROFILES", {}, _on_get_profiles_result)


# --- Gestori delle Risposte dal Server ---

func _on_profile_update_result(payload: Dictionary):
	if payload.get("success"):
		var updated_fields = payload.get("updated_fields", {})
		print("Profilo aggiornato con successo: ", updated_fields)
		# Aggiorna i dati utente locali nel NetworkManager
		NetworkManager.user_data.merge(updated_fields)
		emit_signal("profile_update_success", updated_fields)
	else:
		var reason = payload.get("message", "Errore sconosciuto")
		printerr("Aggiornamento profilo fallito: ", reason)
		emit_signal("profile_update_failed", reason)

func _on_achievement_unlocked_result(payload: Dictionary):
	if payload.get("success"):
		var achievement_id = payload.get("id", "")
		print("Achievement sbloccato: ", achievement_id)
		emit_signal("achievement_unlocked_success", achievement_id)
	else:
		var reason = payload.get("message", "Errore sconosciuto")
		printerr("Sblocco achievement fallito: ", reason)
		emit_signal("achievement_unlocked_failed", reason)

func _on_get_profiles_result(payload: Dictionary):
	if payload.get("success"):
		var profiles = payload.get("profiles", {})
		print("Ricevuti profili: ", profiles)
		emit_signal("profiles_received", profiles)
	else:
		# Gestisci l'errore se necessario
		printerr("Impossibile recuperare i profili: ", payload.get("message", "Errore del server"))
