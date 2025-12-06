extends Node

@onready var panel = $AccessPanel

func _ready():
	# Mostra un messaggio di attesa all'utente. Potresti avere una scena
	# di "caricamento" o "connessione in corso" qui.
	print("GameClient: In attesa della connessione al server...")

	# Connettiti ai segnali del NetworkManager.
	# Questi segnali ci diranno quando la connessione è pronta o se ha fallito.
	NetworkManager.connection_established.connect(_on_connection_established)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	
	# Avvia il primo tentativo di connessione.
	# Il NetworkManager gestirà automaticamente i tentativi di riconnessione se questa dovesse cadere.
	if not NetworkManager.session_token.is_empty():
		NetworkManager.connect_to_server()


func _on_connection_established():
	print("GameClient: Connessione stabilita con successo. Caricamento della scena di login.")
	if panel:
		panel.show()
	else:
		printerr("GameClient: ERRORE - La scena di login non è presente!")

func _on_connection_failed():
	# Questo viene chiamato dopo che tutti i tentativi di riconnessione sono falliti.
	printerr("GameClient: ERRORE - Impossibile connettersi al server. Controlla la connessione e riavvia.")
	# Qui potresti mostrare una schermata di errore all'utente con un pulsante "Riprova" o "Esci".
