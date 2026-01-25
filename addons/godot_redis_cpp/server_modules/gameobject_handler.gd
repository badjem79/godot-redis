# GameObjectHandler.gd
# Handles server-side logic for shared GameObjects, including CRUD operations and ACL management.
extends Node

enum ReadPerm {NONE = 0, OWNER = 1, PUBLIC = 2, CUSTOM = -1}
enum WritePerm {NONE = 0, OWNER = 1, CUSTOM = -1}

func _ready():
	# Register this handler with the BackendServer autoload
	BackendServer.register_handler(self)

func _exit_tree():
	BackendServer.unregister_handler(self)

func get_handled_message_types() -> Array[String]:
	return [
		"GAMEOBJECT_CREATE", "GAMEOBJECT_GET", "GAMEOBJECT_GET_MINE",
		"GAMEOBJECT_UPDATE", "GAMEOBJECT_DELETE",
		"GAMEOBJECT_ACL_ADD", "GAMEOBJECT_ACL_REMOVE"
	]

func handle_message(peer_id: int, msg_type: String, req_id: String, payload: Dictionary, user_id: int):
	match msg_type:
		"GAMEOBJECT_CREATE": _handle_create(peer_id, user_id, req_id, payload)
		"GAMEOBJECT_GET": _handle_get(peer_id, user_id, req_id, payload)
		"GAMEOBJECT_GET_MINE": _handle_get_mine(peer_id, user_id, req_id, payload)
		"GAMEOBJECT_UPDATE": _handle_update(peer_id, user_id, req_id, payload)
		"GAMEOBJECT_DELETE": _handle_delete(peer_id, user_id, req_id, payload)
		"GAMEOBJECT_ACL_ADD": _handle_acl_add(peer_id, user_id, req_id, payload)
		"GAMEOBJECT_ACL_REMOVE": _handle_acl_remove(peer_id, user_id, req_id, payload)

# --- Permissions Helpers ---

func _can_read(user_id: int, object_key: String, object_data: Dictionary) -> bool:
	var owner_id = int(object_data.get("owner_id", -1))
	var perm = int(object_data.get("read_perm", ReadPerm.NONE))
	
	if perm == ReadPerm.PUBLIC:
		return true
	if perm == ReadPerm.OWNER and user_id == owner_id:
		return true
	if perm == ReadPerm.CUSTOM:
		# Check if the user is in the read ACL set
		return BackendServer.redis_client.sismember(object_key + ":read_acl", str(user_id))
		
	return false

func _can_write(user_id: int, object_key: String, object_data: Dictionary) -> bool:
	var owner_id = int(object_data.get("owner_id", -1))
	var perm = int(object_data.get("write_perm", WritePerm.NONE))

	if perm == WritePerm.OWNER and user_id == owner_id:
		return true
	if perm == WritePerm.CUSTOM:
		# Check if the user is in the write ACL set
		return BackendServer.redis_client.sismember(object_key + ":write_acl", str(user_id))
		
	return false

# --- Internal Helpers ---

func create_gameobject_internal(owner_id: int, type: String, data: Dictionary, parent_key: String = "") -> Dictionary:
	"""
	Internal helper to create a GameObject without network context.
	Useful for server-initiated objects like Lobby Game Instances.
	"""
	var new_id = BackendServer.redis_client.increment_value("gameobject:counter:" + type)
	var key = "gameobject:%s:%s" % [type, new_id]

	var object_data = {
		"id": new_id,
		"type": type,
		"owner_id": owner_id,
		"parent": parent_key,
		"read_perm": data.get("read_perm", ReadPerm.OWNER),
		"write_perm": data.get("write_perm", WritePerm.OWNER),
	}
	
	# Merge custom attributes with 'data_' prefix
	for data_key in data:
		if not (data_key in ["read_perm", "write_perm"]):
			object_data["data_" + data_key] = data[data_key]

	BackendServer.redis_client.begin_transaction()
	BackendServer.redis_client.hset_multiple_values(key, object_data)
	
	# Primary owner index
	if owner_id > 0:
		BackendServer.redis_client.sadd_values("user:%s:gameobjects" % owner_id, [key])
		BackendServer.redis_client.sadd_values("user:%s:gameobjects:%s" % [owner_id, type], [key])

	if not parent_key.is_empty():
		BackendServer.redis_client.sadd_values(parent_key + ":children", [key])
	
	var result = BackendServer.redis_client.commit_transaction()
	if result.get("success"):
		object_data["key"] = key
		return object_data
	return {}

# --- Logic Handlers ---

func _handle_get(peer_id: int, user_id: int, req_id: String, payload: Dictionary):
	var keys = payload.get("keys", [])
	var results = {}

	for key in keys:
		var object_data = BackendServer.redis_client.hget_all_values(key)
		if not object_data.is_empty():
			if _can_read(user_id, key, object_data):
				results[key] = object_data
			else:
				results[key] = {"error": "Access denied"}
	
	BackendServer.send_response(peer_id, "GAMEOBJECT_GET_RESULT", req_id, {"success": true, "objects": results})

func _handle_get_mine(peer_id: int, user_id: int, req_id: String, payload: Dictionary):
	var type_filter = payload.get("type", "")
	var index_key = "user:%s:gameobjects" % user_id
	if not type_filter.is_empty():
		index_key += ":" + type_filter

	var object_keys = BackendServer.redis_client.smembers_keys(index_key)
	if object_keys.is_empty():
		BackendServer.send_response(peer_id, "GAMEOBJECT_GET_RESULT", req_id, {"success": true, "objects": {}})
		return
		
	var objects_data = {}
	for key in object_keys:
		objects_data[key] = BackendServer.redis_client.hget_all_values(key)
		
	BackendServer.send_response(peer_id, "GAMEOBJECT_GET_RESULT", req_id, {"success": true, "objects": objects_data})
	
func _handle_create(peer_id: int, user_id: int, req_id: String, payload: Dictionary):
	var type = payload.get("type")
	var data = payload.get("data", {})
	var parent_key = payload.get("parent", "")

	if not type or type.is_empty():
		BackendServer.send_response(peer_id, "GAMEOBJECT_ERROR", req_id, {"message": "Type not specified."})
		return

	var object_data = create_gameobject_internal(user_id, type, data, parent_key)
	if not object_data.is_empty():
		BackendServer.send_response(peer_id, "GAMEOBJECT_CREATE_RESULT", req_id, {"success": true, "object_data": object_data})
	else:
		BackendServer.send_response(peer_id, "GAMEOBJECT_ERROR", req_id, {"message": "Transaction failed."})

func _handle_update(peer_id: int, user_id: int, req_id: String, payload: Dictionary):
	var key = payload.get("key")
	var data_to_update = payload.get("data", {})
	
	var object_data = BackendServer.redis_client.hget_all_values(key)
	if object_data.is_empty():
		BackendServer.send_response(peer_id, "GAMEOBJECT_ERROR", req_id, {"message": "Object not found."})
		return
		
	if not _can_write(user_id, key, object_data):
		BackendServer.send_response(peer_id, "GAMEOBJECT_ERROR", req_id, {"message": "Write permission denied."})
		return
		
	var sanitized_data = {}
	var forbidden_keys = ["id", "type", "owner_id", "parent", "read_perm", "write_perm"]
	for field in data_to_update:
		if not (field in forbidden_keys):
			sanitized_data["data_" + field] = data_to_update[field]
			
	if sanitized_data.is_empty(): return

	BackendServer.redis_client.hset_multiple_values(key, sanitized_data)
	
	var updated_data = BackendServer.redis_client.hget_all_values(key)
	BackendServer.send_response(peer_id, "GAMEOBJECT_UPDATE_RESULT", req_id, {"success": true, "updated_data": updated_data})

func _handle_delete(peer_id: int, user_id: int, req_id: String, payload: Dictionary):
	var key = payload.get("key")
	var object_data = BackendServer.redis_client.hget_all_values(key)
	if object_data.is_empty():
		BackendServer.send_response(peer_id, "GAMEOBJECT_DELETE_RESULT", req_id, {"success": true, "key": key})
		return
	
	var owner_id = int(object_data.get("owner_id", -1))
	if owner_id != user_id:
		BackendServer.send_response(peer_id, "GAMEOBJECT_ERROR", req_id, {"message": "Only the owner can delete this object."})
		return

	var type = object_data.get("type")
	var parent_key = object_data.get("parent")

	BackendServer.redis_client.begin_transaction()
	BackendServer.redis_client.srem_values("user:%s:gameobjects" % owner_id, [key])
	BackendServer.redis_client.srem_values("user:%s:gameobjects:%s" % [owner_id, type], [key])
	if not parent_key.is_empty():
		BackendServer.redis_client.srem_values(parent_key + ":children", [key])
	BackendServer.redis_client.del_keys([key, key + ":children", key + ":read_acl", key + ":write_acl"])
	BackendServer.redis_client.commit_transaction()
	
	BackendServer.send_response(peer_id, "GAMEOBJECT_DELETE_RESULT", req_id, {"success": true, "key": key})

# --- ACL Handlers ---

func _handle_acl_add(peer_id: int, user_id: int, req_id: String, payload: Dictionary):
	var key = payload.get("key")
	var acl_type = payload.get("acl_type") # "read" or "write"
	var target_user_ids = payload.get("user_ids", [])

	if not (acl_type in ["read", "write"]) or target_user_ids.is_empty():
		BackendServer.send_response(peer_id, "GAMEOBJECT_ERROR", req_id, {"message": "Invalid ACL payload."})
		return
		
	var object_data = BackendServer.redis_client.hget_all_values(key)
	if object_data.is_empty():
		BackendServer.send_response(peer_id, "GAMEOBJECT_ERROR", req_id, {"message": "Object not found."})
		return
		
	if int(object_data.get("owner_id", -1)) != user_id:
		BackendServer.send_response(peer_id, "GAMEOBJECT_ERROR", req_id, {"message": "Only the owner can modify ACLs."})
		return

	var acl_key = "%s:%s_acl" % [key, acl_type]
	var members_to_add = []
	for id in target_user_ids:
		members_to_add.append(str(id))

	BackendServer.redis_client.sadd_values(acl_key, members_to_add)

	BackendServer.send_response(peer_id, "GAMEOBJECT_ACL_ADD_RESULT", req_id, {
		"success": true, "key": key, "acl_type": acl_type, "added_users": target_user_ids
	})

func _handle_acl_remove(peer_id: int, user_id: int, req_id: String, payload: Dictionary):
	var key = payload.get("key")
	var acl_type = payload.get("acl_type")
	var target_user_ids = payload.get("user_ids", [])

	if not (acl_type in ["read", "write"]) or target_user_ids.is_empty():
		BackendServer.send_response(peer_id, "GAMEOBJECT_ERROR", req_id, {"message": "Invalid ACL payload."})
		return
		
	var object_data = BackendServer.redis_client.hget_all_values(key)
	if object_data.is_empty():
		BackendServer.send_response(peer_id, "GAMEOBJECT_ERROR", req_id, {"message": "Object not found."})
		return

	if int(object_data.get("owner_id", -1)) != user_id:
		BackendServer.send_response(peer_id, "GAMEOBJECT_ERROR", req_id, {"message": "Only the owner can modify ACLs."})
		return

	var acl_key = "%s:%s_acl" % [key, acl_type]
	var members_to_remove = []
	for id in target_user_ids:
		members_to_remove.append(str(id))

	BackendServer.redis_client.srem_values(acl_key, members_to_remove)

	BackendServer.send_response(peer_id, "GAMEOBJECT_ACL_REMOVE_RESULT", req_id, {
		"success": true, "key": key, "acl_type": acl_type, "removed_users": target_user_ids
	})
