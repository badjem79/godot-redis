class_name LoginHandler
extends Node


func _ready():
	# Registra questo gestore con il server autoload
	BackendServer.register_handler(self)

func _exit_tree():
	BackendServer.unregister_handler(self)

func get_handled_message_types() -> Array[String]:
	return ["REGISTER", "LOGIN", "LOGOUT", "RECONNECT"]
	
func handle_message(peer_id: int, msg_type: String, req_id: String, payload: Dictionary, user_id: int):
	match msg_type:
		"REGISTER":
			_handle_register(peer_id, req_id, payload)
		"LOGIN":
			_handle_login(peer_id, req_id, payload, user_id)
		"RECONNECT":
			_handle_reconnect(peer_id, req_id, payload)
		"LOGOUT":
			_handle_logout(peer_id, req_id)
		_:
			printerr("LoginHandler ha ricevuto un messaggio non gestito: ", msg_type)

		
func _handle_register(peer_id: int, req_id: String, payload: Dictionary):
	"""Gestisce una richiesta di registrazione di un nuovo utente."""
	var username = payload.get("username", "")
	var password = payload.get("password", "")

	# Validazione base dell'input
	if username.length() < 3 or password.length() < 6:
		var reason = "Username deve avere almeno 3 caratteri e password almeno 6."
		BackendServer.send_response(peer_id, "REGISTER_RESULT", req_id, {"success": false, "message": reason})
		return

	# Accedi al RedisClient tramite la variabile esportata del genitore
	var redis_client: RedisClient = BackendServer.redis_client
	if not redis_client:
		printerr("LoginHandler: RedisClient non è disponibile sul server!")
		BackendServer.send_response(peer_id, "REGISTER_RESULT", req_id, {"success": false, "message": "Errore interno del server."})
		return
		
	# --- Logica Atomica di Registrazione ---
	# Per evitare race condition (due utenti che si registrano con lo stesso nome
	# contemporaneamente), dovremmo usare una transazione o un comando atomico.
	# Per ora, usiamo una semplice verifica.
	
	var username_key = "user:username:" + username.to_lower() # Normalizza l'username
	var existing_id = redis_client.get_value(username_key)

	if not existing_id.is_empty():
		BackendServer.send_response(peer_id, "REGISTER_RESULT", req_id, {"success": false, "message": "Username già in uso."})
		return
		
	# --- FASE 1: Ottieni un ID utente unico in modo atomico ---
	# Il comando INCR è atomico di per sé, quindi è sicuro eseguirlo da solo.
	var new_user_id = redis_client.increment_value("global:next_user_id")
	if new_user_id == 0: # L'incremento ha fallito
		printerr("SERVER: Fallimento critico nell'ottenere un nuovo ID utente da Redis.")
		BackendServer.send_response(peer_id, "REGISTER_RESULT", req_id, {"success": false, "message": "Errore interno del server."})
		return
	
	var user_key = "user:" + str(new_user_id)

	# Crea l'hash della password (MAI SALVARE IN CHIARO)
	var password_hash = password.sha256_text()
	
	# Prepara i dati da salvare nell'HASH dell'utente
	var user_data = {
		"id": new_user_id,
		"username": username,
		"password_hash": password_hash,
		"level": 1,
		"created_at": Time.get_unix_time_from_system()
	}
	
	# --- FASE 2: Salva i dati dell'utente in una transazione ---
	# Usiamo WATCH sulla chiave dell'username per evitare race condition
	# se due utenti si registrano con lo stesso nome contemporaneamente.
	redis_client.begin_transaction([username_key])
	redis_client.hset_multiple_values(user_key, user_data)
	redis_client.set_value(username_key, str(new_user_id))

	var result = redis_client.commit_transaction()
	if result.get("success"):
		print("SERVER: Utente '", username, "' registrato con ID ", new_user_id)
		BackendServer.send_response(peer_id, "REGISTER_RESULT", req_id, {"success": true, "message": "Registrazione completata!"})
	else:
		# Potremmo voler implementare una logica di rollback qui
		printerr("SERVER: Fallimento nel salvare i dati per l'utente '", username, "' in Redis.")
		BackendServer.send_response(peer_id, "REGISTER_RESULT", req_id, {"success": false, "message": "Errore interno del server."})


func _handle_login(peer_id: int, req_id: String, payload: Dictionary, current_user_id: int):
	# Se la connessione è già autenticata, non permettere un altro login.
	if current_user_id != -1:
		BackendServer.send_response(peer_id, "LOGIN_RESULT", req_id, {"success": false, "message": "Connessione già autenticata."})
		return

	"""Gestisce una richiesta di login di un utente."""
	var username = payload.get("username", "")
	var password = payload.get("password", "")
	
	if username.is_empty() or password.is_empty():
		BackendServer.send_response(peer_id, "LOGIN_RESULT", req_id, {"success": false, "message": "Credenziali non valide."})
		return

	var redis_client: RedisClient = BackendServer.redis_client
	if not redis_client:
		printerr("LoginHandler: RedisClient non è disponibile sul server!")
		BackendServer.send_response(peer_id, "LOGIN_RESULT", req_id, {"success": false, "message": "Errore interno del server."})
		return

	# 1. Trova l'ID utente dall'username normalizzato
	var username_key = "user:username:" + username.to_lower()
	var user_id_str = redis_client.get_value(username_key)
	
	if user_id_str.is_empty():
		BackendServer.send_response(peer_id, "LOGIN_RESULT", req_id, {"success": false, "message": "Credenziali non valide."})
		return
		
	var user_key = "user:" + user_id_str
	
	# 2. Recupera l'hash della password salvata
	var stored_hash = redis_client.hget_value(user_key, "password_hash")
	
	# 3. Confronta l'hash fornito con quello salvato
	var provided_hash = password.sha256_text()
	
	if stored_hash == provided_hash:
		# Login riuscito!
		var user_id = int(user_id_str)
		# Autentica questa connessione sul server principale
		BackendServer.authenticate_peer(peer_id, user_id)
		# --- Generazione del JWT ---
		if BackendServer.jwt_algorithm == null:
			printerr("SERVER: jwt_algorithm non inizializzato! Impossibile creare il token.")
			BackendServer.send_response(peer_id, "LOGIN_RESULT", req_id, {"success": false, "message": "Errore interno del server."})
			return

		var jwt_builder: JWTBuilder = JWT.create() \
			.with_issuer(BackendServer.JWT_ISSUER) \
			.with_claim("uid", user_id) \
			.with_expires_at(Time.get_unix_time_from_system() + BackendServer.TOKEN_VALIDITY_SECONDS)
		var token: String = jwt_builder.sign(BackendServer.jwt_algorithm)

		# Recupera tutti i dati utente da inviare al client
		var user_data_for_client = redis_client.hget_all_values(user_key)
		# Rimuovi dati sensibili prima di inviarli!
		user_data_for_client.erase("password_hash")
		
		var response_payload = {
			"success": true,
			"message": "Login riuscito!",
			"token": token,
			"user_data": user_data_for_client
		}

		BackendServer.send_response(peer_id, "LOGIN_RESULT", req_id, response_payload)
		print("SERVER: Login riuscito per '", username, "' (Peer ID: ", peer_id, ")")
	else:
		# Password non corretta
		BackendServer.send_response(peer_id, "LOGIN_RESULT", req_id, {"success": false, "message": "Credenziali non valide."})

func _handle_logout(peer_id: int, req_id: String):
	"""Gestisce una richiesta di logout di un utente."""
	print("SERVER: Ricevuta richiesta di logout dal peer ", peer_id)
	# Rimuove l'autenticazione della connessione corrente.
	BackendServer.deauthenticate_peer(peer_id)
	BackendServer.send_response(peer_id, "LOGOUT_RESULT", req_id, {"success": true})

func _handle_reconnect(peer_id: int, req_id: String, payload: Dictionary):
	"""Gestisce un tentativo di ri-autenticazione usando un token."""
	var token = payload.get("token", "")
	if token.is_empty():
		BackendServer.send_response(peer_id, "RECONNECT_RESULT", req_id, {"success": false, "message": "Token mancante."})
		return

	# 1. Verifica se il token è valido (firma e scadenza)
	if not BackendServer.is_token_valid(token):
		BackendServer.send_response(peer_id, "RECONNECT_RESULT", req_id, {"success": false, "message": "Token non valido o scaduto."})
		return

	# 2. Estrai l'ID utente dal token
	var jwt_decoder: JWTDecoder = JWT.decode(token)
	var token_payload_str = JWTUtils.base64URL_decode(jwt_decoder.get_payload()).get_string_from_utf8()
	var token_payload: Dictionary = JSON.parse_string(token_payload_str)
	var user_id = token_payload.get("uid")

	# 3. Autentica la connessione
	BackendServer.authenticate_peer(peer_id, int(user_id))

	# --- NUOVA LOGICA: Rinnova il token per estendere la sessione ---
	var new_token: String = ""
	if BackendServer.jwt_algorithm != null:
		var jwt_builder: JWTBuilder = JWT.create() \
			.with_issuer(BackendServer.JWT_ISSUER) \
			.with_claim("uid", user_id) \
			.with_expires_at(Time.get_unix_time_from_system() + BackendServer.TOKEN_VALIDITY_SECONDS)
		new_token = jwt_builder.sign(BackendServer.jwt_algorithm)
	else:
		BackendServer.send_response(peer_id, "RECONNECT_RESULT", req_id, {"success": false, "message": "SERVER: jwt_algorithm non inizializzato! Impossibile rinnovare il token."})
		printerr("SERVER: jwt_algorithm non inizializzato! Impossibile rinnovare il token.")
		# Non è un errore fatale, la riconnessione funziona lo stesso, ma il token non viene rinnovato.

	# 4. Invia la risposta di successo (con il nuovo token)
	var user_key = "user:" + str(user_id)
	var user_data_for_client = BackendServer.redis_client.hget_all_values(user_key)
	user_data_for_client.erase("password_hash")

	var response_payload = {"success": true, "user_data": user_data_for_client, "token": new_token}
	BackendServer.send_response(peer_id, "RECONNECT_RESULT", req_id, response_payload)
	print("SERVER: Riconnessione riuscita per l'utente ", user_id, " (Peer ID: ", peer_id, "). Token rinnovato.")
