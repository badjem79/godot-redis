extends Node

@onready var server = get_parent()

func get_handled_message_types() -> Array[String]:
	return ["REGISTER", "LOGIN"]
	
func handle_message(peer_id: int, msg_type: String, payload: Dictionary, _token: String):
	match msg_type:
		"REGISTER":
			_handle_register(peer_id, payload)
		"LOGIN":
			_handle_login(peer_id, payload)
		_:
			printerr("LoginHandler ha ricevuto un messaggio non gestito: ", msg_type)
		
func _handle_register(peer_id: int, payload: Dictionary):
	"""Gestisce una richiesta di registrazione di un nuovo utente."""
	var username = payload.get("username", "")
	var password = payload.get("password", "")

	# Validazione base dell'input
	if username.length() < 3 or password.length() < 6:
		var reason = "Username deve avere almeno 3 caratteri e password almeno 6."
		server.send_response(peer_id, "REGISTER_RESULT", {"success": false, "message": reason})
		return

	# Accedi al RedisClient tramite la variabile esportata del genitore
	var rc: RedisClient = server.rc
	if not rc:
		printerr("LoginHandler: RedisClient non è disponibile sul server!")
		server.send_response(peer_id, "REGISTER_RESULT", {"success": false, "message": "Errore interno del server."})
		return
		
	# --- Logica Atomica di Registrazione ---
	# Per evitare race condition (due utenti che si registrano con lo stesso nome
	# contemporaneamente), dovremmo usare una transazione o un comando atomico.
	# Per ora, usiamo una semplice verifica.
	
	var username_key = "user:username:" + username.to_lower() # Normalizza l'username
	var existing_id = rc.get_value(username_key)

	if not existing_id.is_empty():
		server.send_response(peer_id, "REGISTER_RESULT", {"success": false, "message": "Username già in uso."})
		return

	# Genera un nuovo ID utente in modo atomico
	var new_user_id = rc.increment_value("global:next_user_id")
	var user_key = "user:" + str(new_user_id)
	
	# Crea l'hash della password (MAI SALVARE IN CHIARO)
	var password_hash = password.sha256_text()
	
	# Prepara i dati da salvare nell'HASH dell'utente
	var user_data = {
		"id": new_user_id,
		"username": username,
		"password_hash": password_hash,
		"level": 1,
		"gold": 100,
		"created_at": Time.get_unix_time_from_system()
	}
	
	# Salva i dati
	var success_hset = rc.hset_multiple_values(user_key, user_data)
	var success_set = rc.set_value(username_key, str(new_user_id))

	if success_hset and success_set:
		print("SERVER: Utente '", username, "' registrato con ID ", new_user_id)
		server.send_response(peer_id, "REGISTER_RESULT", {"success": true, "message": "Registrazione completata!"})
	else:
		# Potremmo voler implementare una logica di rollback qui
		printerr("SERVER: Fallimento nel salvare i dati per l'utente '", username, "' in Redis.")
		server.send_response(peer_id, "REGISTER_RESULT", {"success": false, "message": "Errore interno del server."})


func _handle_login(peer_id: int, payload: Dictionary):
	"""Gestisce una richiesta di login di un utente."""
	var username = payload.get("username", "")
	var password = payload.get("password", "")
	
	if username.is_empty() or password.is_empty():
		server.send_response(peer_id, "LOGIN_RESULT", {"success": false, "message": "Credenziali non valide."})
		return

	var rc: RedisClient = server.rc
	if not rc:
		printerr("LoginHandler: RedisClient non è disponibile sul server!")
		server.send_response(peer_id, "LOGIN_RESULT", {"success": false, "message": "Errore interno del server."})
		return

	# 1. Trova l'ID utente dall'username normalizzato
	var username_key = "user:username:" + username.to_lower()
	var user_id_str = rc.get_value(username_key)
	
	if user_id_str.is_empty():
		server.send_response(peer_id, "LOGIN_RESULT", {"success": false, "message": "Credenziali non valide."})
		return
		
	var user_key = "user:" + user_id_str
	
	# 2. Recupera l'hash della password salvata
	var stored_hash = rc.hget_value(user_key, "password_hash")
	
	# 3. Confronta l'hash fornito con quello salvato
	var provided_hash = password.sha256_text()
	
	if stored_hash == provided_hash:
		# Login riuscito!
		# Genera un token di sessione (per ora, semplice; in futuro, JWT)
		var token = str(randi()) + str(Time.get_ticks_usec())
		
		# Salva la sessione in Redis (peer_id -> user_id, token, etc.)
		server.authenticate_peer(peer_id, int(user_id_str), token)

		# Recupera tutti i dati utente da inviare al client
		var user_data_for_client = rc.hget_all_values(user_key)
		# Rimuovi dati sensibili prima di inviarli!
		user_data_for_client.erase("password_hash")
		
		var response_payload = {
			"success": true,
			"message": "Login riuscito!",
			"token": token,
			"user_data": user_data_for_client
		}
		server.send_response(peer_id, "LOGIN_RESULT", response_payload)
		print("SERVER: Login riuscito per '", username, "' (Peer ID: ", peer_id, ")")
	else:
		# Password non corretta
		server.send_response(peer_id, "LOGIN_RESULT", {"success": false, "message": "Credenziali non valide."})
