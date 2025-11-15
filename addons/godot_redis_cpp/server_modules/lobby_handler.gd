# LobbyHandler.gd
extends Node

@onready var server = get_parent()
@onready var rc: RedisClient = server.redis_client

func get_handled_message_types() -> Array[String]:
    return [
        # Messaggi esistenti
        "LOBBY_GET_LIST", "LOBBY_CREATE", "LOBBY_JOIN", "LOBBY_LEAVE",
        "LOBBY_SET_READY", "Lobby_START_GAME",
        
        # Nuovi messaggi per il matchmaking
        "MATCHMAKING_JOIN_QUEUE",
        "MATCHMAKING_LEAVE_QUEUE"
    ]


func handle_message(peer_id: int, msg_type: String, payload: Dictionary, token: String):
    var user_id = server.authenticated_peers[peer_id].user_id
    
    # Un giocatore non può fare operazioni sulla lobby se è già in una partita
    var current_lobby_id = rc.hget_value("user:" + str(user_id), "current_lobby_id")
    
    match msg_type:
        "LOBBY_GET_LIST":
            _handle_get_list(peer_id)
        "LOBBY_CREATE":
            _handle_create(peer_id, user_id, payload)
        "LOBBY_JOIN":
            _handle_join(peer_id, user_id, payload, current_lobby_id)
        "LOBBY_LEAVE":
            _handle_leave(peer_id, user_id, current_lobby_id)
        "LOBBY_SET_READY":
            _handle_set_ready(peer_id, user_id, current_lobby_id, payload)
        "LOBBY_START_GAME":
            _handle_start_game(peer_id, user_id, current_lobby_id)

# --- Funzioni Helper ---

func _broadcast_to_lobby(lobby_key: String, msg_type: String, payload: Dictionary, exclude_peer_id: int = 0):
    var player_ids = rc.smembers_keys(lobby_key + ":players")
    for id_str in player_ids:
        var peer_id = server.get_peer_id_from_user_id(int(id_str)) # Il server ha bisogno di questo helper
        if peer_id > 0 and peer_id != exclude_peer_id:
            server.send_response(peer_id, msg_type, payload)

# --- Gestori di Logica ---

func _handle_create(peer_id: int, user_id: int, payload: Dictionary):
    var new_lobby_id = rc.increment_value("global:next_lobby_id")
    var lobby_key = "lobby:" + str(new_lobby_id)
    
    var lobby_data = {
        "id": new_lobby_id,
        "name": payload.get("name", "Nuova Partita"),
        "owner_id": user_id,
        "max_players": clampi(payload.get("max_players", 2), 2, 8),
        "is_private": "1" if payload.get("private", false) else "0",
        "status": "waiting"
    }
    rc.hset_multiple_values(lobby_key, lobby_data)
    
    if not payload.get("private", false):
        rc.zadd_values("lobbies:public", {lobby_key: 1})
    
    # Fai entrare automaticamente il creatore nella lobby
    _join_lobby_logic(peer_id, user_id, lobby_key)

func _handle_join(peer_id: int, user_id: int, payload: Dictionary, current_lobby_id: String):
    if not current_lobby_id.is_empty(): # Già in una lobby
        server.send_response(peer_id, "LOBBY_ERROR", {"message": "Sei già in una lobby."})
        return
    
    var lobby_key = "lobby:" + str(payload.get("id"))
    # ... (Aggiungi controlli: la lobby esiste? non è piena? etc.) ...
    
    _join_lobby_logic(peer_id, user_id, lobby_key)
    
func _join_lobby_logic(peer_id: int, user_id: int, lobby_key: String):
    # Aggiungi il giocatore ai dati della lobby
    rc.begin_transaction()
    rc.sadd_values(lobby_key + ":players", [str(user_id)])
    rc.hset_value("user:" + str(user_id), "current_lobby_id", lobby_key)
    rc.commit_transaction()
    
    # Aggiorna il punteggio (n. giocatori) nell'indice pubblico
    var player_count = rc.scard_count(lobby_key + ":players")
    rc.zadd_values("lobbies:public", {lobby_key: player_count})
    
    # Notifica gli altri giocatori nella lobby
    _broadcast_to_lobby(lobby_key, "LOBBY_PLAYER_JOINED", {"user_id": user_id}, peer_id)
    
    # Invia al nuovo giocatore i dati completi della lobby
    var lobby_data = rc.hget_all_values(lobby_key)
    var player_ids = rc.smembers_keys(lobby_key + ":players")
    server.send_response(peer_id, "LOBBY_JOIN_SUCCESS", {"lobby_data": lobby_data, "players": player_ids})

func _handle_leave(peer_id: int, user_id: int, lobby_key: String):
    if lobby_key.is_empty(): return # Non è in una lobby
    
    rc.begin_transaction()
    rc.srem_values(lobby_key + ":players", [str(user_id)])
    rc.srem_values(lobby_key + ":ready_players", [str(user_id)])
    rc.hdel_values("user:" + str(user_id), ["current_lobby_id"]) # Assumendo un hdel_values
    rc.commit_transaction()

    # Notifica gli altri
    _broadcast_to_lobby(lobby_key, "LOBBY_PLAYER_LEFT", {"user_id": user_id})
    server.send_response(peer_id, "LOBBY_LEAVE_SUCCESS", {})
    
    var player_count = rc.scard_count(lobby_key + ":players")
    if player_count == 0:
        rc.del_keys([lobby_key]) # Cancella la lobby se è vuota
        rc.zrem_values("lobbies:public", [lobby_key])
    else:
        # Aggiorna l'indice
        rc.zadd_values("lobbies:public", {lobby_key: player_count})
        # ... (logica per riassegnare l'owner se necessario) ...

func _handle_set_ready(peer_id: int, user_id: int, lobby_key: String, payload: Dictionary):
    var is_ready = payload.get("ready", false)
    if is_ready:
        rc.sadd_values(lobby_key + ":ready_players", [str(user_id)])
    else:
        rc.srem_values(lobby_key + ":ready_players", [str(user_id)])
        
    _broadcast_to_lobby(lobby_key, "LOBBY_PLAYER_READY", {"user_id": user_id, "is_ready": is_ready})

func _handle_start_game(peer_id: int, user_id: int, lobby_key: String):
    var lobby_data = rc.hget_all_values(lobby_key)
    if int(lobby_data.get("owner_id")) != user_id:
        # Solo l'owner può avviare
        return
        
    var players = rc.smembers_keys(lobby_key + ":players")
    var ready_players = rc.smembers_keys(lobby_key + ":ready_players")
    
    # Tutti devono essere pronti (tranne forse l'owner) e ci deve essere un n. minimo di giocatori
    if players.size() < 2 or players.size() != ready_players.size():
        server.send_response(peer_id, "LOBBY_ERROR", {"message": "Non tutti i giocatori sono pronti."})
        return
        
    # Avvia la partita
    rc.hset_value(lobby_key, "status", "in_game")
    rc.zrem_values("lobbies:public", [lobby_key]) # Rimuovi la lobby dalla lista pubblica
    
    # Qui creeresti un GameInstance, un nuovo GameObject di tipo "game"
    # e notificheresti i giocatori.
    _broadcast_to_lobby(lobby_key, "LOBBY_GAME_START", {"game_id": "game:123"})