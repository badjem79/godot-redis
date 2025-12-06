class_name LoginController
extends Node

# Segnali che questo modulo emette per l'UI (l'interfaccia si connetterà a questi)
signal registration_success
signal registration_failed(reason)
signal login_success(user_data)
signal login_failed(reason)
signal logout_success

func _ready():
	# Il LoginController ora reagisce ai segnali di alto livello del NetworkManager.
	# Quando una sessione viene ripristinata, è a tutti gli effetti un login riuscito.
	NetworkManager.session_reestablished.connect(func(user_data): emit_signal("login_success", user_data))
	# Quando la ri-autenticazione fallisce, è un login fallito.
	NetworkManager.authentication_required.connect(func(reason): emit_signal("login_failed", reason))

	# Avvia il processo di connessione
	# NetworkManager.connect_to_server() # se è già connesso sctta solo la chiamata al segnale

func attempt_login(username: String, password: String):
	"""Invia una richiesta di login al server."""
	if username.is_empty() or password.is_empty():
		emit_signal("login_failed", "Username e password non possono essere vuoti.")
		return
	
	var payload = {"username": username, "password": password}
	NetworkManager.send_message("LOGIN", payload, _on_login_result)

func attempt_register(username: String, password: String):
	"""Invia una richiesta di registrazione al server."""
	if username.is_empty() or password.is_empty():
		emit_signal("registration_failed", "Username e password non possono essere vuoti.")
		return
		
	var payload = {"username": username, "password": password}
	NetworkManager.send_message("REGISTER", payload, _on_register_result)

func attempt_logout():
	"""Invia una richiesta di logout al server."""
	# Non c'è bisogno di un payload, ma inviamo un dizionario vuoto per coerenza.
	NetworkManager.send_message("LOGOUT", {}, _on_logout_result)

# --- Gestori delle Risposte dal Server (chiamati dal NetworkManager) ---

# Questo metodo viene eseguito quando il NetworkManager riceve un messaggio "LOGIN_RESULT"
func _on_login_result(payload: Dictionary): # Corrisponde a "LOGIN_RESULT"
	if payload.get("success"):
		var received_token = payload.get("token", "")
		var received_user_data = payload.get("user_data", {})
		
		if received_token.is_empty() or received_user_data.is_empty():
			# Il server ha inviato una risposta di successo ma malformata
			emit_signal("login_failed", "Risposta del server non valida.")
			return
		
		# Memorizza il JWT e i dati utente nel NetworkManager per l'uso globale
		NetworkManager.session_token = received_token
		NetworkManager.save_token_to_file() # <-- SALVA IL TOKEN
		NetworkManager.user_data = received_user_data
		
		emit_signal("login_success", received_user_data)
	else:
		emit_signal("login_failed", payload.get("message", "Credenziali non valide o errore del server."))

# Questo metodo viene eseguito quando il NetworkManager riceve un messaggio "REGISTER_RESULT"
func _on_register_result(payload: Dictionary): # Corrisponde a "REGISTER_RESULT"
	if payload.get("success"):
		emit_signal("registration_success")
	else:
		emit_signal("registration_failed", payload.get("message", "Registrazione fallita."))

# Questo metodo viene eseguito quando il NetworkManager riceve un messaggio "LOGOUT_RESULT"
func _on_logout_result(payload: Dictionary): # Corrisponde a "LOGOUT_RESULT"
	if payload.get("success"):
		print("CLIENT: Logout confermato dal server.")
	else:
		# Anche se il logout fallisce lato server (improbabile), forziamo la pulizia lato client.
		printerr("LoginController: Il server ha risposto con un fallimento al logout. Forzatura logout locale.")
	
	# La cosa più importante per il logout è distruggere il token lato client.
	NetworkManager.session_token = ""
	NetworkManager.delete_token_file() # <-- CANCELLA IL TOKEN
	NetworkManager.user_data = {}
	emit_signal("logout_success")
