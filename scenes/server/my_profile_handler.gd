class_name MyProfileHandler
extends "res://addons/godot_redis_cpp/server_modules/profile_handler.gd"

#=============================================================================
# OVERRIDE DELLE FUNZIONI DI VALIDAZIONE
#=============================================================================

func _can_unlock_achievement(_user_id: int, achievement_id: String) -> bool:
	"""
	Sovrascriviamo la logica di validazione degli achievement.
	Qui implementiamo le regole specifiche del nostro gioco.
	"""
	
	var achievement_data: Achievement = AchievementRegistry.get_achievement(achievement_id)
	
	# 1. Controlla se l'achievement esiste
	if not achievement_data:
		print("SERVER: Tentativo di sblocco per un achievement inesistente: ", achievement_id)
		return false

	# 2. Controlla se il client ha il permesso di richiedere lo sblocco.
	# Se 'false', solo la logica interna del server può sbloccarlo (es. level up).
	if not achievement_data.is_client_unlockable:
		print("SERVER: Il client non può sbloccare l'achievement '%s' direttamente." % achievement_id)
		return false

	# --- Logica Specifica del Gioco ---
	# Se arriviamo qui, significa che l'achievement è 'client_unlockable'.
	# Ora possiamo aggiungere controlli specifici se necessario, o semplicemente approvare.

	# Per questo esempio, approviamo tutti gli achievement che sono 'client_unlockable'.
	return true
