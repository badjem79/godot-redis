# GameObjectHandler.gd
class_name GameObjectHandler
extends Node

@onready var server = get_parent()
@onready var rc: RedisClient = server.redis_client

enum ReadPerm {NONE = 0, OWNER = 1, PUBLIC = 2, CUSTOM = -1}
enum WritePerm {NONE = 0, OWNER = 1, CUSTOM = -1}

func get_handled_message_types() -> Array[String]:
    return [
        "GAMEOBJECT_CREATE", "GAMEOBJECT_GET", "GAMEOBJECT_GET_MINE",
        "GAMEOBJECT_UPDATE", "GAMEOBJECT_DELETE",
        "GAMEOBJECT_ACL_ADD", "GAMEOBJECT_ACL_REMOVE"
    ]

func handle_message(peer_id: int, msg_type: String, payload: Dictionary, token: String):
    var user_id = server.authenticated_peers[peer_id].user_id

    match msg_type:
        "GAMEOBJECT_CREATE": _handle_create(peer_id, user_id, payload)
        "GAMEOBJECT_GET": _handle_get(peer_id, user_id, payload)
        "GAMEOBJECT_GET_MINE": _handle_get_mine(peer_id, user_id, payload)
        "GAMEOBJECT_UPDATE": _handle_update(peer_id, user_id, payload)
        "GAMEOBJECT_DELETE": _handle_delete(peer_id, user_id, payload)
        "GAMEOBJECT_ACL_ADD": _handle_acl_add(peer_id, user_id, payload)
        "GAMEOBJECT_ACL_REMOVE": _handle_acl_remove(peer_id, user_id, payload)

# --- FUNZIONI HELPER PER I PERMESSI (AGGIORNATE) ---

func _can_read(user_id: int, object_key: String, object_data: Dictionary) -> bool:
    var owner_id = int(object_data.get("owner_id", -1))
    var perm = int(object_data.get("read_perm", ReadPerm.NONE))
    
    if perm == ReadPerm.PUBLIC:
        return true
    if perm == ReadPerm.OWNER and user_id == owner_id:
        return true
    if perm == ReadPerm.CUSTOM:
        # Controlla se l'utente è nella lista ACL di lettura
        return rc.sismember(object_key + ":read_acl", str(user_id))
        
    return false

func _can_write(user_id: int, object_key: String, object_data: Dictionary) -> bool:
    var owner_id = int(object_data.get("owner_id", -1))
    var perm = int(object_data.get("write_perm", WritePerm.NONE))

    if perm == WritePerm.OWNER and user_id == owner_id:
        return true
    if perm == WritePerm.CUSTOM:
        # Controlla se l'utente è nella lista ACL di scrittura
        return rc.sismember(object_key + ":write_acl", str(user_id))
        
    return false

# --- GESTORI DI LOGICA (con modifiche) ---

func _handle_get(peer_id: int, user_id: int, payload: Dictionary):
    var keys = payload.get("keys", [])
    var results = {}

    for key in keys:
        var object_data = rc.hget_all_values(key)
        if not object_data.is_empty():
            # Passiamo anche la chiave per il controllo ACL
            if _can_read(user_id, key, object_data):
                results[key] = object_data
            else:
                results[key] = {"error": "Accesso in lettura negato"}
    
    server.send_response(peer_id, "GAMEOBJECT_GET_RESULT", {"success": true, "objects": results})

func _handle_get_mine(peer_id: int, user_id: int, payload: Dictionary):
    var type_filter = payload.get("type", "")
    
    var index_key: String
    if not type_filter.is_empty():
        # Usa l'indice specifico per tipo
        index_key = "user:%s:gameobjects:%s" % [user_id, type_filter]
    else:
        # Usa l'indice principale
        index_key = "user:%s:gameobjects" % user_id

    # 1. Recupera tutte le chiavi degli oggetti dall'indice
    var object_keys = rc.smembers_keys(index_key)
    
    if object_keys.is_empty():
        server.send_response(peer_id, "GAMEOBJECT_GET_RESULT", {"success": true, "objects": {}})
        return
        
    # 2. Recupera tutti gli HASH corrispondenti
    # (Qui una pipeline sarebbe ideale, ma usiamo un ciclo per ora)
    var objects_data = {}
    for key in object_keys:
        objects_data[key] = rc.hget_all_values(key)
        
    # Non serve controllare i permessi, perché stiamo cercando
    # gli oggetti del richiedente stesso.
    
    server.send_response(peer_id, "GAMEOBJECT_GET_RESULT", {"success": true, "objects": objects_data})
    
func _handle_create(peer_id: int, user_id: int, payload: Dictionary):
    var type = payload.get("type")
    var data = payload.get("data", {})
    var parent_key = payload.get("parent", "")

    # Validazione di base
    if not type or type.is_empty():
        server.send_response(peer_id, "GAMEOBJECT_ERROR", {"message": "Tipo di oggetto non specificato."})
        return

    # Genera un nuovo ID per questo tipo di oggetto
    var new_id = rc.increment_value("gameobject:counter:" + type)
    var key = "gameobject:%s:%s" % [type, new_id]

    # Prepara l'HASH con i metadati fondamentali
    var object_data = {
        "id": new_id,
        "type": type,
        "owner_id": user_id,
        "parent": parent_key,
        "read_perm": data.get("read_perm", ReadPerm.OWNER),
        "write_perm": data.get("write_perm", WritePerm.OWNER),
    }
    
    # Unisci i dati custom forniti dal client, prefissandoli
    for data_key in data:
        if not (data_key in ["read_perm", "write_perm"]):
            object_data["data_" + data_key] = data[data_key]

    # Usiamo una transazione per assicurare che l'oggetto e i suoi indici
    # vengano creati in modo atomico.
    rc.begin_transaction()

    # 1. Crea l'HASH dell'oggetto
    rc.hset_multiple_values(key, object_data)
    
    # 2. Aggiungi l'oggetto all'indice principale del proprietario
    rc.sadd_values("user:%s:gameobjects" % user_id, [key])

    # 3. Aggiungi l'oggetto all'indice specifico per tipo del proprietario
    rc.sadd_values("user:%s:gameobjects:%s" % [user_id, type], [key])

    # 4. Se ha un genitore, aggiungilo al set dei figli del genitore
    if not parent_key.is_empty():
        rc.sadd_values(parent_key + ":children", [key])
    
    var result = rc.commit_transaction()

    if result.get("success"):
        server.send_response(peer_id, "GAMEOBJECT_CREATE_RESULT", {"success": true, "object_data": object_data})
    else:
        server.send_response(peer_id, "GAMEOBJECT_ERROR", {"message": "Fallimento nella creazione dell'oggetto (transazione)."})

func _handle_update(peer_id: int, user_id: int, payload: Dictionary):
    var key = payload.get("key")
    var object_data = rc.hget_all_values(key)
    if object_data.is_empty():
        server.send_response(peer_id, "GAMEOBJECT_ERROR", {"message": "Oggetto non trovato."})
        return
        
    if not _can_write(user_id, key, object_data):
        server.send_response(peer_id, "GAMEOBJECT_ERROR", {"message": "Permesso di scrittura negato."})
        return
        
    # Filtra per evitare di sovrascrivere metadati fondamentali
    var sanitized_data = {}
    var forbidden_keys = ["id", "type", "owner_id", "parent", "read_perm", "write_perm"]
    for field in data_to_update:
        if not (field in forbidden_keys):
            sanitized_data["data_" + field] = data_to_update[field]
            
    if sanitized_data.is_empty(): return # Niente da aggiornare

    rc.hset_multiple_values(key, sanitized_data)
    
    # Invia indietro l'oggetto aggiornato
    var updated_data = rc.hget_all_values(key)
    server.send_response(peer_id, "GAMEOBJECT_UPDATE_RESULT", {"success": true, "updated_data": updated_data})

func _handle_delete(peer_id: int, user_id: int, payload: Dictionary):
    var key = payload.get("key")
    var object_data = rc.hget_all_values(key)
    if object_data.is_empty():
        server.send_response(peer_id, "GAMEOBJECT_DELETE_RESULT", {"success": true, "key": key})
        return # Se non esiste, va bene così
    
    var owner_id = int(object_data.get("owner_id", -1))
    var type = object_data.get("type")
    var parent_key = object_data.get("parent")

    # Solo il proprietario può cancellare
    if owner_id != user_id:
        server.send_response(peer_id, "GAMEOBJECT_ERROR", {"message": "Solo il proprietario può cancellare l'oggetto."})
        return

    # --- AGGIORNAMENTO DEGLI INDICI ---
    rc.begin_transaction()

    # 1. Rimuovi l'oggetto dall'indice principale del proprietario
    rc.srem_values("user:%s:gameobjects" % owner_id, [key])
    
    # 2. Rimuovi l'oggetto dall'indice specifico per tipo
    rc.srem_values("user:%s:gameobjects:%s" % [owner_id, type], [key])
        
    # 3. Rimuovi l'oggetto dal set di figli del suo genitore
    if not parent_key.is_empty():
        rc.srem_values(parent_key + ":children", [key])
        
    # 4. Cancella l'HASH principale e tutti i suoi set associati (children, ACLs)
    # NOTA: Per cancellare i figli ricorsivamente servirebbe una logica più complessa
    rc.del_keys([key, key + ":children", key + ":read_acl", key + ":write_acl"])

    var result = rc.commit_transaction()
    # --- FINE AGGIORNAMENTO INDICI ---
    
    server.send_response(peer_id, "GAMEOBJECT_DELETE_RESULT", {"success": true, "key": key})

# --- NUOVI GESTORI PER LE ACL ---

func _handle_acl_add(peer_id: int, user_id: int, payload: Dictionary):
    var key = payload.get("key")
    var acl_type = payload.get("acl_type") # "read" o "write"
    var target_user_ids = payload.get("user_ids", []) # Array di ID da aggiungere

    if not (acl_type in ["read", "write"]) or target_user_ids.is_empty():
        server.send_response(peer_id, "GAMEOBJECT_ERROR", {"message": "Payload ACL non valido."})
        return
        
    var object_data = rc.hget_all_values(key)
    if object_data.is_empty(): # ... (errore oggetto non trovato) ...
        return
        
    # Solo il PROPRIETARIO può modificare le ACL
    if int(object_data.get("owner_id", -1)) != user_id:
        server.send_response(peer_id, "GAMEOBJECT_ERROR", {"message": "Solo il proprietario può modificare le ACL."})
        return

    var acl_key = "%s:%s_acl" % [key, acl_type]
    
    # Converte gli ID in stringhe per Redis
    var members_to_add = []
    for id in target_user_ids:
        members_to_add.append(str(id))

    rc.sadd_values(acl_key, members_to_add)

    server.send_response(peer_id, "GAMEOBJECT_ACL_ADD_RESULT", {
        "success": true,
        "key": key,
        "acl_type": acl_type,
        "added_users": target_user_ids
    })

func _handle_acl_remove(peer_id: int, user_id: int, payload: Dictionary):
    var key = payload.get("key")
    var acl_type = payload.get("acl_type")
    var target_user_ids = payload.get("user_ids", [])

    if not (acl_type in ["read", "write"]) or target_user_ids.is_empty():
        server.send_response(peer_id, "GAMEOBJECT_ERROR", {"message": "Payload ACL non valido."})
        return
        
    var object_data = rc.hget_all_values(key)
    if object_data.is_empty():
        server.send_response(peer_id, "GAMEOBJECT_ERROR", {"message": "Oggetto non trovato."})
        return

    # Solo il proprietario può modificare le ACL
    if int(object_data.get("owner_id", -1)) != user_id:
        server.send_response(peer_id, "GAMEOBJECT_ERROR", {"message": "Solo il proprietario può modificare le ACL."})
        return

    var acl_key = "%s:%s_acl" % [key, acl_type]
    
    var members_to_remove = []
    for id in target_user_ids:
        members_to_remove.append(str(id))

    rc.srem_values(acl_key, members_to_remove)

    server.send_response(peer_id, "GAMEOBJECT_ACL_REMOVE_RESULT", {
        "success": true,
        "key": key,
        "acl_type": acl_type,
        "removed_users": target_user_ids
    })