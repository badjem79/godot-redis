@tool
extends EditorPlugin

func _enter_tree():
	add_custom_type("BackendServer", "Node", preload("res://addons/godot_redis_cpp/backend_server.gd"), preload("res://addons/godot_redis_cpp/icons/redis_icon.svg"))
	add_custom_type("LoginHandler", "Node", preload("res://addons/godot_redis_cpp/server_modules/login_handler.gd"), preload("res://addons/godot_redis_cpp/icons/server_icon.svg"))
	
	add_custom_type("NetworkManager", "Node", preload("res://addons/godot_redis_cpp/network_manager.gd"), preload("res://addons/godot_redis_cpp/icons/database_client.svg"))
	add_custom_type("LoginController", "Node", preload("res://addons/godot_redis_cpp/client_modules/login_controller.gd"), preload("res://addons/godot_redis_cpp/icons/database_client.svg"))

func _exit_tree():
	remove_custom_type("BackendServer")
	remove_custom_type("LoginHandler")
	
	remove_custom_type("NetworkManager")
	remove_custom_type("LoginController")
