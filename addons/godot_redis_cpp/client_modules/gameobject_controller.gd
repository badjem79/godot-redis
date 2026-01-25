# GameObjectController.gd
# Handles client-side GameObject lifecycle and synchronization.
extends Node

# Signals for server responses
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
		# Dynamically bind handlers, e.g. "GAMEOBJECT_CREATE_RESULT" -> "_on_gameobject_create_result"
		NetworkManager.register_handler(msg_type, Callable(self, "_on_" + msg_type.to_lower()))

func _exit_tree():
	for msg_type in _registered_handlers:
		NetworkManager.unregister_handler(msg_type)

# --- Public API ---

func create_object(type: String, data: Dictionary, parent_key: String = ""):
	"""Requests the creation of a new client-owned GameObject."""
	var payload = {
		"type": type,
		"data": data,
		"parent": parent_key
	}
	NetworkManager.send_message("GAMEOBJECT_CREATE", payload, _on_gameobject_create_result)

func get_objects(keys: Array):
	"""Requests data for one or more GameObjects by their keys."""
	if keys.is_empty(): return
	NetworkManager.send_message("GAMEOBJECT_GET", {"keys": keys}, _on_gameobject_get_result)
	
func get_my_objects(type_filter: String = ""):
	"""Requests all GameObjects owned by the current user."""
	NetworkManager.send_message("GAMEOBJECT_GET_MINE", {"type": type_filter}, _on_gameobject_get_result)

func update_object(key: String, data: Dictionary):
	"""Requests an update for specific fields of a GameObject."""
	if data.is_empty(): return
	var payload = {"key": key, "data": data}
	NetworkManager.send_message("GAMEOBJECT_UPDATE", payload, _on_gameobject_update_result)
	
func delete_object(key: String):
	"""Requests the deletion of a GameObject."""
	NetworkManager.send_message("GAMEOBJECT_DELETE", {"key": key}, _on_gameobject_delete_result)

func add_to_acl(object_key: String, acl_type: String, user_ids: Array):
	"""
	Adds users to an Access Control List.
	acl_type: "read" or "write"
	"""
	var payload = {
		"key": object_key,
		"acl_type": acl_type,
		"user_ids": user_ids
	}
	NetworkManager.send_message("GAMEOBJECT_ACL_ADD", payload, _on_gameobject_acl_add_result)

func remove_from_acl(object_key: String, acl_type: String, user_ids: Array):
	"""Removes users from an Access Control List."""
	var payload = {
		"key": object_key,
		"acl_type": acl_type,
		"user_ids": user_ids
	}
	NetworkManager.send_message("GAMEOBJECT_ACL_REMOVE", payload, _on_gameobject_acl_remove_result)

# --- Response Handlers ---

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
	var reason = payload.get("message", "Unknown error from GameObjectHandler.")
	printerr("GameObject operation failed: ", reason)
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
