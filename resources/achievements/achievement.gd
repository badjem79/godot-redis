class_name Achievement
extends Resource

# L'ID univoco dell'achievement. Es: "first_login", "level_10_reached".
@export var id: String = ""

# Il titolo visualizzato nella UI. Es: "Primo Accesso".
@export var title: String = ""

# La descrizione di come sbloccare l'achievement. Es: "Completa il tuo primo login."
@export var description: String = ""

# Un'icona da mostrare nella UI (opzionale).
@export var icon: Texture2D

# Se 'true', il client può richiedere lo sblocco di questo achievement.
# Se 'false', può essere sbloccato solo da logica interna del server (es. un level up).
@export var is_client_unlockable: bool = true
