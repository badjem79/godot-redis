extends Node

# Dizionario per accedere rapidamente ai dati di un achievement tramite il suo ID.
var achievements: Dictionary = {}

const ACHIEVEMENT_PATH = "res://resources/achievements/"

func _ready() -> void:
	_load_achievements()

func _load_achievements() -> void:
	print("Caricamento achievements da: ", ACHIEVEMENT_PATH)
	var dir = DirAccess.open(ACHIEVEMENT_PATH)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".tres"):
				var achievement: Achievement = load(dir.get_current_dir() + "/" + file_name)
				if achievement and not achievement.id.is_empty():
					achievements[achievement.id] = achievement
					print(" - Achievement caricato: ", achievement.id)
			file_name = dir.get_next()
	else:
		printerr("Impossibile trovare la cartella degli achievements: ", ACHIEVEMENT_PATH)

func get_achievement(id: String) -> Achievement:
	"""Restituisce la risorsa Achievement corrispondente a un ID."""
	return achievements.get(id, null)

func get_all_achievements() -> Dictionary:
	"""Restituisce tutti gli achievements caricati."""
	return achievements
