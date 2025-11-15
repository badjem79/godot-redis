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

	await get_tree().create_timer(0.1).timeout
	await run_del_test()
	
	await get_tree().create_timer(0.1).timeout
	await run_set_tests()
	
	await get_tree().create_timer(0.1).timeout
	await run_sorted_set_tests()
	
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
# In uno script di test

func run_del_test():
	var key1 = "test:key:to:delete:1"
	var key2 = "test:key:to:delete:2"

	print("\n--- ESECUZIONE TEST DEL ---")

	# 1. Crea alcune chiavi
	print("\n1. Creo due chiavi di test...")
	set_value(key1, "hello")
	set_value(key2, "world")

	# Verifica che esistano
	var val1 = get_value(key1)
	var val2 = get_value(key2)
	print("   > Valori prima di DEL: '", val1, "', '", val2, "'")
	if val1.is_empty() or val2.is_empty():
		printerr("   > ERRORE: Le chiavi non sono state create correttamente.")
		return

	await get_tree().create_timer(0.1).timeout

	# 2. Elimina le chiavi
	print("\n2. Eseguo del_keys su entrambe le chiavi...")
	var success = del_keys([key1, key2])
	print("   > Operazione DEL riuscita: ", success)
	
	await get_tree().create_timer(0.1).timeout

	# 3. Verifica che siano state eliminate
	val1 = get_value(key1)
	val2 = get_value(key2)
	print("   > Valori dopo DEL: '", val1, "', '", val2, "'")

	if val1.is_empty() and val2.is_empty():
		print("   > RISULTATO: OK! Le chiavi sono state eliminate.")
	else:
		printerr("   > RISULTATO: FALLITO! Una o più chiavi esistono ancora.")
		
func run_set_tests():
	# Assumendo che rc sia un riferimento valido al tuo RedisClient
	var players_online_key = "online_players"
	
	print("\n--- ESECUZIONE TEST SET ---")
	
	del_keys([players_online_key])
	
	# 1. Test SADD (con il nuovo nome sadd_values)
	print("\n1. Test SADD:")
	var players_to_add = ["user:101", "user:102", "user:103"]
	print("   > Aggiungo i giocatori: ", players_to_add)
	var success_add = sadd_values(players_online_key, players_to_add)
	print("   > Operazione SADD riuscita: ", success_add)
	
	await get_tree().create_timer(0.1).timeout
	
	# 2. Test SMEMBERS (con il nuovo nome smembers_keys)
	print("\n2. Test SMEMBERS:")
	var online_players = smembers_keys(players_online_key)
	print("   > Giocatori online recuperati: ", online_players)
	# Nota: i SET non hanno un ordine, quindi il controllo rimane basato su size e 'has'
	if online_players.size() == 3 and online_players.has("user:102"):
		print("   > RISULTATO: OK!")
	else:
		printerr("   > RISULTATO: FALLITO!")

	# 3. Test SREM (con il nuovo nome srem_values)
	print("\n3. Test SREM:")
	var players_to_remove = ["user:102"]
	print("   > Rimuovo il giocatore: ", players_to_remove)
	var success_rem = srem_values(players_online_key, players_to_remove)
	print("   > Operazione SREM riuscita: ", success_rem)
	
	await get_tree().create_timer(0.1).timeout
	
	online_players = smembers_keys(players_online_key)
	print("   > Giocatori online dopo la rimozione: ", online_players)
	if online_players.size() == 2 and not online_players.has("user:102"):
		print("   > RISULTATO: OK!")
	else:
		printerr("   > RISULTATO: FALLITO!")

func run_scard_test():
	var test_set_key = "test:scard_set"
	
	print("\n--- ESECUZIONE TEST SCARD ---")
	
	# 1. Pulisci la chiave per un test pulito
	del_keys([test_set_key])
	await get_tree().create_timer(0.1).timeout

	# 2. Controlla il conteggio su una chiave inesistente (deve essere 0)
	var count = scard_count(test_set_key)
	print("   > Conteggio su chiave inesistente: ", count)
	if count != 0:
		printerr("   > RISULTATO: FALLITO! Il conteggio dovrebbe essere 0.")
		return

	# 3. Aggiungi alcuni membri
	var members_to_add = ["alpha", "beta", "gamma"]
	sadd_values(test_set_key, members_to_add)
	print("   > Aggiunti 3 membri: ", members_to_add)
	await get_tree().create_timer(0.1).timeout
	
	# 4. Controlla il conteggio (deve essere 3)
	count = scard_count(test_set_key)
	print("   > Conteggio dopo l'aggiunta: ", count)
	if count != 3:
		printerr("   > RISULTATO: FALLITO! Il conteggio dovrebbe essere 3.")
		return
		
	# 5. Aggiungi un membro duplicato e uno nuovo
	sadd_values(test_set_key, ["gamma", "delta"]) # 'gamma' è un duplicato
	print("   > Aggiunti 'gamma' (duplicato) and 'delta' (nuovo)")
	await get_tree().create_timer(0.1).timeout

	# 6. Controlla il conteggio finale (deve essere 4)
	count = scard_count(test_set_key)
	print("   > Conteggio finale: ", count)
	if count == 4:
		print("   > RISULTATO: OK!")
	else:
		printerr("   > RISULTATO: FALLITO! Il conteggio dovrebbe essere 4.")

func run_sorted_set_tests():
	var leaderboard_key = "leaderboard:season1"
	
	print("\n--- ESECUZIONE TEST SORTED SET (LEADERBOARD) ---")
	
	del_keys([leaderboard_key]) # Pulisci per un test pulito
	
	# 1. Test ZADD (con zadd_values)
	print("\n1. Test ZADD:")
	var players_scores = {
		"user:101": 1500, # Alice
		"user:102": 1850, # Bob
		"user:103": 1200, # Charlie
		"user:104": 2100 # Diana
	}
	print("   > Aggiungo punteggi dei giocatori: ", players_scores)
	zadd_values(leaderboard_key, players_scores)
	
	# Aggiorniamo il punteggio di un giocatore
	zadd_values(leaderboard_key, {"user:101": 1550}) # Alice vince una partita
	
	await get_tree().create_timer(0.1).timeout
	
	# 2. Test ZREVRANGE (per ottenere la top 3)
	print("\n2. Test ZREVRANGE (Top 3):")
	var top_3_with_scores = zrevrange_values(leaderboard_key, 0, 2, true)
	print("   > Classifica Top 3 (con punteggi): ", top_3_with_scores)
	
	# Verifichiamo che Diana sia la prima
	var top_player = top_3_with_scores.keys()[0]
	if top_3_with_scores.size() == 3 and top_player == "user:104":
		print("   > RISULTATO: OK!")
	else:
		printerr("   > RISULTATO: FALLITO!")

	# 3. Test ZREM (con zrem_values)
	print("\n3. Test ZREM:")
	var player_to_remove = ["user:103"] # Charlie viene bannato
	print("   > Rimuovo il giocatore: ", player_to_remove)
	zrem_values(leaderboard_key, player_to_remove)

	await get_tree().create_timer(0.1).timeout
	
	var top_players_after_rem = zrevrange_values(leaderboard_key, 0, -1) # Ottieni tutti
	print("   > Classifica dopo la rimozione: ", top_players_after_rem)
	if top_players_after_rem.size() == 3 and not top_players_after_rem.has("user:103"):
		print("   > RISULTATO: OK!")
	else:
		printerr("   > RISULTATO: FALLITO!")
