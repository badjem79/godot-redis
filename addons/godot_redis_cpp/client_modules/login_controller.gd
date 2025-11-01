class_name LoginController
extends Node

# Segnali che questo modulo emette per l'UI (l'interfaccia si connetterà a questi)
signal registration_success
signal registration_failed(reason)
signal login_success(user_data)
signal login_failed(reason)

# Riferimento al genitore (NetworkManager) per comodità
@onready var network_manager = get_parent()

func _ready() -> void:
	network_manager.register_handler("REGISTER_RESULT", Callable(self, "_on_register_result"))
	network_manager.register_handler("LOGIN_RESULT", Callable(self, "_on_login_result"))

# --- API Pubblica di questo Modulo (chiamata dall'UI) ---

func attempt_login(username: String, password: String):
	"""Invia una richiesta di login al server."""
	if username.is_empty() or password.is_empty():
		emit_signal("login_failed", "Username e password non possono essere vuoti.")
		return
	
	var payload = {"username": username, "password": password}
	network_manager.send_message("LOGIN", payload)

func attempt_register(username: String, password: String):
	"""Invia una richiesta di registrazione al server."""
	if username.is_empty() or password.is_empty():
		emit_signal("registration_failed", "Username e password non possono essere vuoti.")
		return
		
	var payload = {"username": username, "password": password}
	network_manager.send_message("REGISTER", payload)

# --- Gestori delle Risposte dal Server (chiamati dal NetworkManager) ---

# Questo metodo viene eseguito quando il NetworkManager riceve un messaggio "LOGIN_RESULT"
func _on_login_result(payload: Dictionary):
	if payload.get("success"):
		var received_token = payload.get("token", "")
		var received_user_data = payload.get("user_data", {})
		
		if received_token.is_empty() or received_user_data.is_empty():
			# Il server ha inviato una risposta di successo ma malformata
			emit_signal("login_failed", "Risposta del server non valida.")
			return
		
		# Memorizza il token e i dati utente nel NetworkManager per l'uso globale
		network_manager.session_token = received_token
		network_manager.user_data = received_user_data
		
		emit_signal("login_success", received_user_data)
	else:
		emit_signal("login_failed", payload.get("message", "Credenziali non valide o errore del server."))

# Questo metodo viene eseguito quando il NetworkManager riceve un messaggio "REGISTER_RESULT"
func _on_register_result(payload: Dictionary):
	if payload.get("success"):
		emit_signal("registration_success")
	else:
		emit_signal("registration_failed", payload.get("message", "Registrazione fallita."))
