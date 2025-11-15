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

@onready var network_manager = get_parent()

func register_self_with_network_manager():
    network_manager.register_handler("GAMEOBJECT_CREATE_RESULT", Callable(self, "_on_create_result"))
    network_manager.register_handler("GAMEOBJECT_GET_RESULT", Callable(self, "_on_get_result"))
    network_manager.register_handler("GAMEOBJECT_UPDATE_RESULT", Callable(self, "_on_update_result"))
    network_manager.register_handler("GAMEOBJECT_DELETE_RESULT", Callable(self, "_on_delete_result"))
    network_manager.register_handler("GAMEOBJECT_ERROR", Callable(self, "_on_error"))
    network_manager.register_handler("GAMEOBJECT_ACL_ADD_RESULT", Callable(self, "_on_acl_add_result"))
    network_manager.register_handler("GAMEOBJECT_ACL_REMOVE_RESULT", Callable(self, "_on_acl_remove_result"))


# --- API PUBBLICA DEL CONTROLLER ---

func create_object(type: String, data: Dictionary, parent_key: String = ""):
    """Richiede la creazione di un nuovo GameObject."""
    var payload = {
        "type": type,
        "data": data,
        "parent": parent_key
    }
    network_manager.send_message("GAMEOBJECT_CREATE", payload)

func get_objects(keys: Array):
    """Richiede i dati di uno o più GameObjects."""
    if keys.is_empty(): return
    network_manager.send_message("GAMEOBJECT_GET", {"keys": keys})
    
func get_my_objects(type_filter: String = ""):
    """
    Richiede tutti i GameObject posseduti dall'utente corrente.
    Se type_filter è specificato, richiede solo oggetti di quel tipo.
    """
    network_manager.send_message("GAMEOBJECT_GET_MINE", {"type": type_filter})

func update_object(key: String, data: Dictionary):
    """Richiede l'aggiornamento dei dati di un GameObject esistente."""
    if data.is_empty(): return
    var payload = {"key": key, "data": data}
    network_manager.send_message("GAMEOBJECT_UPDATE", payload)
    
func delete_object(key: String):
    """Richiede la cancellazione di un GameObject."""
    network_manager.send_message("GAMEOBJECT_DELETE", {"key": key})

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
    network_manager.send_message("GAMEOBJECT_ACL_ADD", payload)

func remove_from_acl(object_key: String, acl_type: String, user_ids: Array):
    """Rimuove utenti da una lista di controllo accessi."""
    var payload = {
        "key": object_key,
        "acl_type": acl_type,
        "user_ids": user_ids
    }
    network_manager.send_message("GAMEOBJECT_ACL_REMOVE", payload)

# --- GESTORI DELLE RISPOSTE ---

func _on_create_result(payload):
    if payload.get("success"):
        emit_signal("object_created", payload.get("object_data"))
    else:
        _on_error(payload)

func _on_get_result(payload):
    if payload.get("success"):
        emit_signal("objects_received", payload.get("objects"))
    else:
        _on_error(payload)

func _on_update_result(payload):
    if payload.get("success"):
        emit_signal("object_updated", payload.get("updated_data"))
    else:
        _on_error(payload)
        
func _on_delete_result(payload):
    if payload.get("success"):
        emit_signal("object_deleted", payload.get("key"))
    else:
        _on_error(payload)

func _on_error(payload):
    var reason = payload.get("message", "Errore sconosciuto dal GameObjectHandler.")
    printerr("GameObject operazione fallita: ", reason)
    emit_signal("operation_failed", reason)

func _on_acl_add_result(payload):
    if payload.get("success"):
        emit_signal("acl_add_success", payload)
    else:
        _on_error(payload)

func _on_acl_remove_result(payload):
    if payload.get("success"):
        emit_signal("acl_remove_success", payload)
    else:
        _on_error(payload)