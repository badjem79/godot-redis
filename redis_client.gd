extends RedisClient

@export var test := false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	print("--- Script di Test per RedisClient avviato ---")
	connection_status_changed.connect(_on_redis_connection_status_changed)
	
	print("--connesso? ", is_connected())
	
	connect_to_redis()

# Questa funzione verrà chiamata automaticamente quando il segnale "connection_status_changed"
# viene emesso dal nostro plugin C++.
func _on_redis_connection_status_changed(connected: bool, message: String):
	print("Stato della connessione ricevuto: ", "CONNESSO" if connected else "FALLITO")
	print("Messaggio dal plugin: ", message)
	
	if is_connected:
		# La connessione è andata a buon fine! Ora possiamo lavorare con Redis.
		if test:
			await run_redis_tests()
		else:
			print("In attesa di comandi")
	else:
		# La connessione è fallita. Stampiamo un errore.
		printerr("Impossibile connettersi a Redis. Controllare che il server sia in esecuzione.")

# per dare a Redis il tempo di elaborare i comandi tra un test e l'altro.
func run_redis_tests() -> void:
	print("\n--- ESECUZIONE TEST REDIS ---")
	
	# === TEST 1: SET e GET di una stringa ===
	var player_key = "player:godot:1"
	var player_name = "CapitanGDExtension"
	print("\n1. Test SET/GET:")
	print("   > Sto salvando il valore '", player_name, "' nella chiave '", player_key, "'")
	var success = set_value(player_key, player_name)
	print("   > Operazione SET riuscita: ", success)
	
	await get_tree().create_timer(0.1).timeout
	
	var retrieved_name = get_value(player_key)
	print("   > Valore recuperato: '", retrieved_name, "'")
	if retrieved_name == player_name:
		print("   > RISULTATO: OK!")
	else:
		printerr("   > RISULTATO: FALLITO! I valori non corrispondono.")

	# === TEST 2: INCREMENT di un valore numerico (punteggio) ===
	var score_key = "player:godot:1:score"
	print("\n2. Test INCREMENT:")
	print("   > Imposto il punteggio iniziale a 100...")
	set_value(score_key, "100") # I valori numerici vengono salvati come stringhe
	
	await get_tree().create_timer(0.1).timeout
	
	print("   > Incremento il punteggio di 50...")
	var new_score = increment_value(score_key, 50)
	print("   > Nuovo punteggio restituito da INCR: ", new_score)

	await get_tree().create_timer(0.1).timeout
	
	var final_score_str = get_value(score_key)
	print("   > Valore finale letto dal DB: '", final_score_str, "'")
	if int(final_score_str) == 150:
		print("   > RISULTATO: OK!")
	else:
		printerr("   > RISULTATO: FALLITO! Il punteggio non è corretto.")
	
	await get_tree().create_timer(0.1).timeout
	await run_hash_and_scan_tests()
	
	await get_tree().create_timer(0.1).timeout
	await run_transaction_test()
	
	print("\n--- TEST REDIS COMPLETATI ---")
	
func run_hash_and_scan_tests() -> void:
	print("\n--- ESECUZIONE TEST HASH e SCAN ---")
	
	# === TEST 3: HASHES per dati di un utente ===
	var user_key = "user:123"
	print("\n3. Test HASH:")
	print("   > Imposto i dati per l'utente '", user_key, "'")
	hset_value(user_key, "username", "PlayerOne")
	hset_value(user_key, "level", "5")
	hset_value(user_key, "class", "Warrior")
	
	await get_tree().create_timer(0.1).timeout
	
	print("   > Recupero il campo 'username'...")
	var username = hget_value(user_key, "username")
	print("   > Username recuperato: '", username, "'")
	if username == "PlayerOne":
		print("   > RISULTATO HGET: OK!")
	else:
		printerr("   > RISULTATO HGET: FALLITO!")

	await get_tree().create_timer(0.1).timeout

	print("   > Recupero tutti i dati dell'utente con HGETALL...")
	var user_data = hget_all_values(user_key)
	print("   > Dati recuperati (Dizionario): ", user_data)
	if user_data.size() == 3 and user_data.get("class") == "Warrior":
		print("   > RISULTATO HGETALL: OK!")
	else:
		printerr("   > RISULTATO HGETALL: FALLITO!")
		
	# === TEST 4: SCAN per trovare le chiavi utente ===
	print("\n4. Test SCAN:")
	# Creiamo un'altra chiave utente per avere più risultati
	hset_value("user:456", "username", "PlayerTwo")
	
	await get_tree().create_timer(0.1).timeout
	
	print("   > Eseguo SCAN con pattern 'user:*'...")
	var user_keys = scan_keys("user:*")
	print("   > Chiavi trovate (Array): ", user_keys)
	
	if user_keys.size() >= 2 and "user:123" in user_keys and "user:456" in user_keys:
		print("   > RISULTATO SCAN: OK!")
	else:
		printerr("   > RISULTATO SCAN: FALLITO!")

func run_transaction_test() -> void:
	print("\n--- ESECUZIONE TEST TRANSAZIONE ---")
	
	# Prepariamo le chiavi
	var account_a = "account:1"
	var account_b = "account:2"
	set_value(account_a, "100")
	set_value(account_b, "50")

	print("\n5. Test Transazione (successo):")
	print("   > Saldo iniziale A: ", get_value(account_a), " | Saldo B: ", get_value(account_b))
	
	await get_tree().create_timer(0.1).timeout

	# Inizia la transazione, osservando i due conti
	var success_begin = begin_transaction([account_a, account_b])
	if not success_begin:
		printerr("   > Fallimento nell'iniziare la transazione!")
		return
	
	print("   > Transazione iniziata. Trasferisco 20 da A a B...")
	# Questi comandi vengono solo accodati, non eseguiti
	increment_value(account_a, -20)
	increment_value(account_b, 20)
	
	await get_tree().create_timer(0.1).timeout
	
	# Esegui la transazione
	var result = commit_transaction()
	print("   > Commit risultato: ", result)
	
	await get_tree().create_timer(0.1).timeout
	if result.get("success"):
		print("   > Saldo finale A: ", get_value(account_a), " | Saldo B: ", get_value(account_b))
		if int(get_value(account_a)) == 80 and int(get_value(account_b)) == 70:
			print("   > RISULTATO: OK!")
		else:
			printerr("   > RISULTATO: FALLITO! I saldi non sono corretti.")
	else:
		printerr("   > RISULTATO: FALLITO! Il commit non è riuscito.")
	
	# TEST DI FALLIMENTO (opzionale ma consigliato)
	# Qui dovresti lanciare un altro client (o usare redis-cli) per modificare
	# una delle chiavi 'watched' mentre la transazione è aperta per vedere il fallimento.
