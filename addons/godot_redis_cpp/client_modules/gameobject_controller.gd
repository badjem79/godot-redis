# GameObjectController.gd
extends Node

# Segnali per le risposte del server
signal object_created(data)
signal objects_received(objects)
signal object_updated(data)
signal object_deleted(key)
signal operation_failed(reason)
signal acl_add_success(data)
signal acl_remove_success(data)

var _registered_handlers = [
	"GAMEOBJECT_CREATE_RESULT",
	"GAMEOBJECT_GET_RESULT",
	"GAMEOBJECT_UPDATE_RESULT",
	"GAMEOBJECT_DELETE_RESULT",
	"GAMEOBJECT_ERROR",
	"GAMEOBJECT_ACL_ADD_RESULT",
	"GAMEOBJECT_ACL_REMOVE_RESULT"
]

func _ready():
	for msg_type in _registered_handlers:
		NetworkManager.register_handler(msg_type, Callable(self, "_on_" + msg_type.to_lower()))

func _exit_tree():
	for msg_type in _registered_handlers:
		NetworkManager.unregister_handler(msg_type)


# --- API PUBBLICA DEL CONTROLLER ---

func create_object(type: String, data: Dictionary, parent_key: String = ""):
	"""Richiede la creazione di un nuovo GameObject."""
	var payload = {
		"type": type,
		"data": data,
		"parent": parent_key
	}
	NetworkManager.send_message("GAMEOBJECT_CREATE", payload, _on_gameobject_create_result)

func get_objects(keys: Array):
	"""Richiede i dati di uno o più GameObjects."""
	if keys.is_empty(): return
	NetworkManager.send_message("GAMEOBJECT_GET", {"keys": keys}, _on_gameobject_get_result)
	
func get_my_objects(type_filter: String = ""):
	"""
	Richiede tutti i GameObject posseduti dall'utente corrente.
	Se type_filter è specificato, richiede solo oggetti di quel tipo.
	"""
	NetworkManager.send_message("GAMEOBJECT_GET_MINE", {"type": type_filter}, _on_gameobject_get_result)

func update_object(key: String, data: Dictionary):
	"""Richiede l'aggiornamento dei dati di un GameObject esistente."""
	if data.is_empty(): return
	var payload = {"key": key, "data": data}
	NetworkManager.send_message("GAMEOBJECT_UPDATE", payload, _on_gameobject_update_result)
	
func delete_object(key: String):
	"""Richiede la cancellazione di un GameObject."""
	NetworkManager.send_message("GAMEOBJECT_DELETE", {"key": key}, _on_gameobject_delete_result)
func add_to_acl(object_key: String, acl_type: String, user_ids: Array):
	"""
	Aggiunge utenti a una lista di controllo accessi.
	acl_type può essere "read" o "write".
	"""
	var payload = {
		"key": object_key,
		"acl_type": acl_type,
		"user_ids": user_ids
	}
	NetworkManager.send_message("GAMEOBJECT_ACL_ADD", payload, _on_gameobject_acl_add_result)

func remove_from_acl(object_key: String, acl_type: String, user_ids: Array):
	"""Rimuove utenti da una lista di controllo accessi."""
	var payload = {
		"key": object_key,
		"acl_type": acl_type,
		"user_ids": user_ids
	}
	NetworkManager.send_message("GAMEOBJECT_ACL_REMOVE", payload, _on_gameobject_acl_remove_result)

# --- GESTORI DELLE RISPOSTE ---

func _on_gameobject_create_result(payload):
	if payload.get("success"):
		emit_signal("object_created", payload.get("object_data"))
	else:
		_on_gameobject_error(payload)

func _on_gameobject_get_result(payload):
	if payload.get("success"):
		emit_signal("objects_received", payload.get("objects"))
	else:
		_on_gameobject_error(payload)

func _on_gameobject_update_result(payload):
	if payload.get("success"):
		emit_signal("object_updated", payload.get("updated_data"))
	else:
		_on_gameobject_error(payload)
		
func _on_gameobject_delete_result(payload):
	if payload.get("success"):
		emit_signal("object_deleted", payload.get("key"))
	else:
		_on_gameobject_error(payload)

func _on_gameobject_error(payload):
	var reason = payload.get("message", "Errore sconosciuto dal GameObjectHandler.")
	printerr("GameObject operazione fallita: ", reason)
	emit_signal("operation_failed", reason)

func _on_gameobject_acl_add_result(payload):
	if payload.get("success"):
		emit_signal("acl_add_success", payload)
	else:
		_on_gameobject_error(payload)

func _on_gameobject_acl_remove_result(payload):
	if payload.get("success"):
		emit_signal("acl_remove_success", payload)
	else:
		_on_gameobject_error(payload)
