extends Node2D

func _ready():
	var args := OS.get_cmdline_args()

	
	if "--server" in args:
		get_tree().change_scene_to_file.call_deferred("res://scenes/server/game_server.tscn")
		return

	if "--client" in args:
		for arg in args: # gestione multi utente
			if arg.begins_with("-inst_name="):
				NetworkManager.game_instance_name = arg.split("=")[1]
				NetworkManager.load_token_from_file()

		get_tree().change_scene_to_file.call_deferred("res://scenes/client/game_client.tscn")
		return
		
	# in caso contrario partono gli unit test di redis...
	get_tree().change_scene_to_file.call_deferred("res://scenes/redis_client_unit_tests.tscn")
