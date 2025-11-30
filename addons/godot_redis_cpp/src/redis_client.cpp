// src/redis_client.cpp
#include "redis_client.h"
#include <godot_cpp/core/class_db.hpp>

using namespace godot;

RedisClient::RedisClient() {}
RedisClient::~RedisClient() {}

void RedisClient::_bind_methods() {

    // 1. Bind dei metodi getter e setter per 'host'
    ClassDB::bind_method(D_METHOD("get_host"), &RedisClient::get_host);
    ClassDB::bind_method(D_METHOD("set_host", "p_host"), &RedisClient::set_host);
    // 2. Aggiungi la proprietà 'host' all'Inspector
    ADD_PROPERTY(PropertyInfo(Variant::STRING, "host"), "set_host", "get_host");

    // 1. Bind dei metodi getter e setter per 'port'
    ClassDB::bind_method(D_METHOD("get_port"), &RedisClient::get_port);
    ClassDB::bind_method(D_METHOD("set_port", "p_port"), &RedisClient::set_port);
    // 2. Aggiungi la proprietà 'port' all'Inspector
    //    Aggiungiamo un HINT per limitare il range di porte valide (es. 1-65535)
    ADD_PROPERTY(PropertyInfo(Variant::INT, "port", PROPERTY_HINT_RANGE, "1,65535,1"), "set_port", "get_port");

    // 1. Bind dei metodi getter e setter per 'auto_connect'
    ClassDB::bind_method(D_METHOD("get_auto_connect"), &RedisClient::get_auto_connect);
    ClassDB::bind_method(D_METHOD("set_auto_connect", "p_auto_connect"), &RedisClient::set_auto_connect);
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "auto_connect"), "set_auto_connect", "get_auto_connect");

    // --- FINE REGISTRAZIONE PROPRIETÀ ---

    // Metodi esposti a GDScript
    ClassDB::bind_method(D_METHOD("connect_to_redis"), &RedisClient::connect_to_redis);

    ClassDB::bind_method(D_METHOD("set_value", "key", "value"), &RedisClient::set_value);
    ClassDB::bind_method(D_METHOD("get_value", "key"), &RedisClient::get_value);
    ClassDB::bind_method(D_METHOD("increment_value", "key", "amount"), &RedisClient::increment_value, DEFVAL(1));

    // HASHES
    ClassDB::bind_method(D_METHOD("hset_value", "key", "field", "value"), &RedisClient::hset_value);
    ClassDB::bind_method(D_METHOD("hget_value", "key", "field"), &RedisClient::hget_value);
    ClassDB::bind_method(D_METHOD("hdel_values", "key", "fields"), &RedisClient::hdel_values);
    ClassDB::bind_method(D_METHOD("hset_multiple_values", "key", "data"), &RedisClient::hset_multiple_values);
    ClassDB::bind_method(D_METHOD("hget_all_values", "key"), &RedisClient::hget_all_values);

    // --- BIND DEI METODI PER I SET ---
    ClassDB::bind_method(D_METHOD("sadd_values", "key", "members"), &RedisClient::sadd_values);
    ClassDB::bind_method(D_METHOD("srem_values", "key", "members"), &RedisClient::srem_values);
    ClassDB::bind_method(D_METHOD("smembers_keys", "key"), &RedisClient::smembers_keys);
    ClassDB::bind_method(D_METHOD("scard_count", "key"), &RedisClient::scard_count);
    ClassDB::bind_method(D_METHOD("sismember", "key", "member"), &RedisClient::sismember);

    // --- BIND DEI METODI PER I SORTED SET (ZSET) ---
    ClassDB::bind_method(D_METHOD("zadd_values", "key", "members_scores"), &RedisClient::zadd_values);
    ClassDB::bind_method(D_METHOD("zrem_values", "key", "members"), &RedisClient::zrem_values);
    ClassDB::bind_method(D_METHOD("zrange_values", "key", "start", "stop", "with_scores"), &RedisClient::zrange_values, DEFVAL(false));
    ClassDB::bind_method(D_METHOD("zrevrange_values", "key", "start", "stop", "with_scores"), &RedisClient::zrevrange_values, DEFVAL(false));

    // SCAN
    ClassDB::bind_method(D_METHOD("scan_keys", "pattern", "count"), &RedisClient::scan_keys, DEFVAL(10));
    ClassDB::bind_method(D_METHOD("is_connected"), &RedisClient::is_connected);
    
    // --- BIND DEI METODI DI TRANSAZIONE ---
    ClassDB::bind_method(D_METHOD("begin_transaction", "keys_to_watch"), &RedisClient::begin_transaction, DEFVAL(Array()));
    ClassDB::bind_method(D_METHOD("commit_transaction"), &RedisClient::commit_transaction);
    ClassDB::bind_method(D_METHOD("discard_transaction"), &RedisClient::discard_transaction);
    ClassDB::bind_method(D_METHOD("is_in_transaction"), &RedisClient::is_in_transaction);

    // --- BIND DEL METODO DEL ---
    ClassDB::bind_method(D_METHOD("del_keys", "keys"), &RedisClient::del_keys);

    // Segnale per notificare il risultato della connessione
    ADD_SIGNAL(MethodInfo("connection_status_changed", PropertyInfo(Variant::BOOL, "is_connected"), PropertyInfo(Variant::STRING, "message")));

    // Metodo privato chiamato tramite call_deferred
    ClassDB::bind_method(D_METHOD("_connection_finished", "success", "message"), &RedisClient::_connection_finished);
}

void RedisClient::_ready() {
    if (auto_connect) {
        UtilityFunctions::print("[Redis C++] Inizializzazione, tentativo di connessione automatica...");
        connect_to_redis();
    }
}

void RedisClient::_exit_tree() {
    // Chiude la connessione se l'oggetto viene distrutto
    if (_redis_client) {
        _redis_client.reset();
        UtilityFunctions::print("[Redis C++] Connessione a Redis chiusa.");
    }
}

// --- IMPLEMENTAZIONE DEI NUOVI GETTER E SETTER ---
void RedisClient::set_host(const String& p_host) {
    host = p_host;
}
String RedisClient::get_host() const {
    return host;
}
void RedisClient::set_port(int p_port) {
    port = p_port;
}
int RedisClient::get_port() const {
    return port;
}
void RedisClient::set_auto_connect(bool p_auto_connect) {
    auto_connect = p_auto_connect;
}
bool RedisClient::get_auto_connect() const {
    return auto_connect;
}
// --- FINE IMPLEMENTAZIONE GETTER/SETTER ---

bool RedisClient::is_connected() {
    return _redis_client != nullptr;
}

void RedisClient::connect_to_redis() {

    // Eseguiamo la connessione in un thread separato per non bloccare mai il gioco.
    std::thread connect_thread([this]() {
        try {
            sw::redis::ConnectionOptions opts;
            opts.host = this->host.utf8().get_data();
            opts.port = this->port;
            opts.socket_timeout = std::chrono::milliseconds(2000); // Timeout 2 sec

            _redis_client = std::make_unique<sw::redis::Redis>(opts);
            
            // Un ping è il modo migliore per verificare se la connessione è viva.
            _redis_client->ping();
            
            // Usa call_deferred per eseguire il codice sul thread principale di Godot
            this->call_deferred("_connection_finished", true, "Connesso a Redis con successo, mitico!");

        } catch (const sw::redis::Error &e) {
            String error_message = "[Redis C++] Errore di connessione: ";
            error_message += e.what();
            this->call_deferred("_connection_finished", false, error_message);
        }
    });
    connect_thread.detach(); // Il thread continuerà l'esecuzione in background
}

void RedisClient::_connection_finished(bool success, const String& message) {
    if (!success) {
        _redis_client.reset(); // Assicura che il puntatore sia nullo in caso di fallimento
    }
    UtilityFunctions::print(message);
    emit_signal("connection_status_changed", success, message);
}

bool RedisClient::set_value(const String& key, const String& value) {
    if (!is_connected()) return false;
    
    try {
        if (is_in_transaction()) {
            // Modalità Transazione: accoda il comando
            _transaction->set(key.utf8().get_data(), value.utf8().get_data());
            return true; // Indica che il comando è stato accodato
        } else {
            // Modalità Normale: esegui subito
            return _redis_client->set(key.utf8().get_data(), value.utf8().get_data());
        }
    } catch (const sw::redis::Error &e) {
        String error_message = "[Redis C++] Errore in set_value: ";
        error_message += e.what();
        UtilityFunctions::push_error(error_message);
        return false;
    }
}

String RedisClient::get_value(const String& key) {
    if (!is_connected()) return "";
    try {
        auto val = _redis_client->get(key.utf8().get_data());
        if (val) {
            // Metodo compatibile per creare una stringa da un buffer UTF-8
            String result;
            return result.utf8(val->c_str(), val->length());
        } else {
            return String(); // Restituisce stringa vuota se non esiste
        }
    } catch (const sw::redis::Error &e) {
        UtilityFunctions::print("[Redis C++] Errore in get_value: ", e.what());
        return "";
    }
}

int64_t RedisClient::increment_value(const String& key, int64_t amount) {
    if (!is_connected()) return 0;
    try {
        if (is_in_transaction()) {
            // Modalità Transazione: accoda il comando
            _transaction->incrby(key.utf8().get_data(), amount);
            return true; // Indica che il comando è stato accodato
        } else {
            // Modalità Normale: esegui subito
            return _redis_client->incrby(key.utf8().get_data(), amount);
        }
    } catch (const sw::redis::Error &e) {
        UtilityFunctions::print("[Redis C++] Errore in increment_value: ", e.what());
        return 0;
    }
}

// HSET: Imposta un campo in un hash
bool RedisClient::hset_value(const String& key, const String& field, const String& value) {
    if (!is_connected()) return false;
    try {
        if (is_in_transaction()) {
            // Modalità Transazione: accoda il comando
            _transaction->hset(key.utf8().get_data(), field.utf8().get_data(), value.utf8().get_data());
            return true; // Indica che il comando è stato accodato
        } else {
            // Modalità Normale: esegui subito
            return _redis_client->hset(key.utf8().get_data(), field.utf8().get_data(), value.utf8().get_data());
        }
        return true;
    } catch (const sw::redis::Error &e) {
        String error_message = "[Redis C++] Errore in hset_value: ";
        error_message += e.what();
        UtilityFunctions::push_error(error_message);
        return false;
    }
}

// HGET: Ottiene un singolo campo da un hash
String RedisClient::hget_value(const String& key, const String& field) {
    if (!is_connected()) return "";
    try {
        auto val = _redis_client->hget(key.utf8().get_data(), field.utf8().get_data());
        if (val) {
            String result;
            return result.utf8(val->c_str(), val->length());
        } else {
            return String(); // Restituisce stringa vuota se non trovato
        }
    } catch (const sw::redis::Error &e) {
        String error_message = "[Redis C++] Errore in hget_value: ";
        error_message += e.what();
        UtilityFunctions::push_error(error_message);
        return "";
    }
}

// HDEL: Rimuove un campo da un hash
bool RedisClient::hdel_values(const String& key, const Array& fields) {
    if (!is_connected() || fields.is_empty()) {
        return false;
    }

    try {
        // Converti l'Array di Godot in un contenitore C++
        std::vector<std::string> fields_vec;
        fields_vec.reserve(fields.size());
        for (int i = 0; i < fields.size(); ++i) {
            fields_vec.push_back(String(fields[i]).utf8().get_data());
        }

        if (is_in_transaction()) {
            // Modalità Transazione
            _transaction->hdel(key.utf8().get_data(), fields_vec.begin(), fields_vec.end());
        } else {
            // Modalità Normale
            _redis_client->hdel(key.utf8().get_data(), fields_vec.begin(), fields_vec.end());
        }
        return true;
    } catch (const sw::redis::Error &e) {
        String error_message = "[Redis C++] Errore in hdel_values: ";
        error_message += e.what();
        UtilityFunctions::push_error(error_message);
        return false;
    }
}

bool RedisClient::hset_multiple_values(const String& key, const Dictionary& data) {
    if (!is_connected()) return false;

    try {
        // 1. Convertiamo il Dictionary di Godot in un contenitore C++ che redis-plus-plus capisce.
        //    Un std::vector<std::pair<std::string, std::string>> è perfetto.
        std::vector<std::pair<std::string, std::string>> fields_values;
        Array keys = data.keys();
        for (int i = 0; i < keys.size(); ++i) {
            String dict_key = keys[i];
            String dict_val = data[keys[i]];
            fields_values.emplace_back(dict_key.utf8().get_data(), dict_val.utf8().get_data());
        }

        if (fields_values.empty()) {
            return true; // Nessun dato da inserire, operazione riuscita.
        }
        if (is_in_transaction()) {
            // Modalità Transazione: accoda il comando
            _transaction->hset(key.utf8().get_data(), fields_values.begin(), fields_values.end());
            return true; // Indica che il comando è stato accodato
        }

        // Modalità Normale: esegui subito
        // 2. Chiamiamo hset con gli iteratori del nostro vector.
        _redis_client->hset(key.utf8().get_data(), fields_values.begin(), fields_values.end());

        return true;
    } catch (const sw::redis::Error &e) {
        String error_message = "[Redis C++] Errore in hset_multiple_values: ";
        error_message += e.what();
        UtilityFunctions::push_error(error_message);
        return false;
    }
}

// HGETALL: Ottiene tutti i campi e valori da un hash
Dictionary RedisClient::hget_all_values(const String& key) {
    Dictionary result;
    if (!is_connected()) return result;
    try {
        std::unordered_map<std::string, std::string> items;
        _redis_client->hgetall(key.utf8().get_data(), std::inserter(items, items.end()));
        
        for (const auto& pair : items) {
            String gd_key;
            String gd_value;

            result[gd_key.utf8(pair.first.c_str(), pair.first.length())] = gd_value.utf8(pair.second.c_str(), pair.second.length());
        }
    } catch (const sw::redis::Error &e) {
        String error_message = "[Redis C++] Errore in hget_all_values: ";
        error_message += e.what();
        UtilityFunctions::push_error(error_message);
    }
    return result;
}

bool RedisClient::sadd_values(const String& key, const Array& members) {
    if (!is_connected() || members.is_empty()) return false;
    
    try {
        std::vector<std::string> member_vec;
        member_vec.reserve(members.size());
        for (int i = 0; i < members.size(); ++i) {
            member_vec.push_back(String(members[i]).utf8().get_data());
        }

        if (is_in_transaction()) {
            _transaction->sadd(key.utf8().get_data(), member_vec.begin(), member_vec.end());
        } else {
            _redis_client->sadd(key.utf8().get_data(), member_vec.begin(), member_vec.end());
        }
        return true;
    } catch (const sw::redis::Error &e) {
        String error_message = "[Redis C++] Errore in sadd_values: ";
        error_message += e.what();
        UtilityFunctions::push_error(error_message);
        return false;
    }
}

bool RedisClient::srem_values(const String& key, const Array& members) {
    if (!is_connected() || members.is_empty()) return false;

    try {
        std::vector<std::string> member_vec;
        member_vec.reserve(members.size());
        for (int i = 0; i < members.size(); ++i) {
            member_vec.push_back(String(members[i]).utf8().get_data());
        }

        if (is_in_transaction()) {
            _transaction->srem(key.utf8().get_data(), member_vec.begin(), member_vec.end());
        } else {
            _redis_client->srem(key.utf8().get_data(), member_vec.begin(), member_vec.end());
        }
        return true;
    } catch (const sw::redis::Error &e) {
        String error_message = "[Redis C++] Errore in srem_values: ";
        error_message += e.what();
        UtilityFunctions::push_error(error_message);
        return false;
    }
}

Array RedisClient::smembers_keys(const String& key) {
    Array keys_array;
    if (!is_connected()) return keys_array;

    try {
        std::vector<std::string> member_vec;
        _redis_client->smembers(key.utf8().get_data(), std::back_inserter(member_vec));
        
        for (const auto& member : member_vec) {
            String gd_member;
            keys_array.push_back(gd_member.utf8(member.c_str(), member.length()));
        }
    } catch (const sw::redis::Error &e) {
        String error_message = "[Redis C++] Errore in smembers_keys: ";
        error_message += e.what();
        UtilityFunctions::push_error(error_message);
    }
    
    return keys_array;
}

int64_t RedisClient::scard_count(const String& key) {
    if (!is_connected()) {
       return 0; // Se non siamo connessi, un set ha 0 elementi
    }

    try {
        // Il comando scard di redis-plus-plus restituisce un long long,
        // che è compatibile con il nostro int64_t.
        return _redis_client->scard(key.utf8().get_data());
    } catch (const sw::redis::Error &e) {
        String error_message = "[Redis C++] Errore in scard_count: ";
        error_message += e.what();
        UtilityFunctions::push_error(error_message);
        return 0; // Restituisce 0 in caso di errore
    }
}

bool RedisClient::sismember(const String& key, const String& member) {
    if (!is_connected()) return false;

    try {
        return _redis_client->sismember(key.utf8().get_data(), member.utf8().get_data());
    } catch (const sw::redis::Error &e) {
        String error_message = "[Redis C++] Errore in sismember: ";
        error_message += e.what();
        UtilityFunctions::push_error(error_message);
        return false;
    }
}

bool RedisClient::zadd_values(const String& key, const Dictionary& members_scores) {
    if (!is_connected() || members_scores.is_empty()) return false;

    try {
        // Converti il Dictionary in un contenitore C++ per redis-plus-plus
        std::unordered_map<std::string, double> m_s_map;
        Array keys = members_scores.keys();
        for (int i = 0; i < keys.size(); ++i) {
            String member = keys[i];
            double score = members_scores[keys[i]];
            m_s_map[member.utf8().get_data()] = score;
        }

        if (is_in_transaction()) {
            _transaction->zadd(key.utf8().get_data(), m_s_map.begin(), m_s_map.end());
        } else {
            _redis_client->zadd(key.utf8().get_data(), m_s_map.begin(), m_s_map.end());
        }
        return true;
    } catch (const sw::redis::Error &e) {
        String error_message = "[Redis C++] Errore in zadd_values: ";
        error_message += e.what();
        UtilityFunctions::push_error(error_message);
    }
    return false;
}

bool RedisClient::zrem_values(const String& key, const Array& members) {
    if (!is_connected() || members.is_empty()) return false;

    try {
        std::vector<std::string> member_vec;
        member_vec.reserve(members.size());
        for (int i = 0; i < members.size(); ++i) {
            member_vec.push_back(String(members[i]).utf8().get_data());
        }

        if (is_in_transaction()) {
            _transaction->zrem(key.utf8().get_data(), member_vec.begin(), member_vec.end());
        } else {
            _redis_client->zrem(key.utf8().get_data(), member_vec.begin(), member_vec.end());
        }
        return true;
    } catch (const sw::redis::Error &e) {
        String error_message = "[Redis C++] Errore in zrem_values: ";
        error_message += e.what();
        UtilityFunctions::push_error(error_message);
    }
    return false;
}

Variant RedisClient::zrange_values(const String& key, int64_t start, int64_t stop, bool with_scores) {

    try {
        if (with_scores) {
            Dictionary result;
            std::vector<std::pair<std::string, double>> values;
            _redis_client->zrange(key.utf8().get_data(), start, stop, std::back_inserter(values));
            for (const auto& pair : values) {
                String gd_key;
                result[gd_key.utf8(pair.first.c_str(), pair.first.length())] = pair.second;
            }
            return result;
        } else {
            Array result;
            std::vector<std::string> values;
            _redis_client->zrange(key.utf8().get_data(), start, stop, std::back_inserter(values));
            for (const auto& val : values) {
                String gd_val;
                result.push_back(gd_val.utf8(val.c_str(), val.length()));
            }
            return result;
        }
    } catch (const sw::redis::Error &e) {
        String error_message = "[Redis C++] Errore in zrange_values: ";
        error_message += e.what();
        UtilityFunctions::push_error(error_message);
    }

    return with_scores ? Variant(Dictionary()) : Variant(Array());
}

Variant RedisClient::zrevrange_values(const String& key, int64_t start, int64_t stop, bool with_scores) {

    try {
        if (with_scores) {
            Dictionary result;
            std::vector<std::pair<std::string, double>> values;
            _redis_client->zrevrange(key.utf8().get_data(), start, stop, std::back_inserter(values));
            for (const auto& pair : values) {
                String gd_key;
                result[gd_key.utf8(pair.first.c_str(), pair.first.length())] = pair.second;
            }
            return result;
        } else {
            Array result;
            std::vector<std::string> values;
            _redis_client->zrevrange(key.utf8().get_data(), start, stop, std::back_inserter(values));
            for (const auto& val : values) {
                String gd_val;
                result.push_back(gd_val.utf8(val.c_str(), val.length()));
            }
            return result;
        }
    } catch (const sw::redis::Error &e) {
        String error_message = "[Redis C++] Errore in zrevrange_values: ";
        error_message += e.what();
        UtilityFunctions::push_error(error_message);
    }

    return with_scores ? Variant(Dictionary()) : Variant(Array());
}

// SCAN: Scansiona le chiavi in modo sicuro
Array RedisClient::scan_keys(const String& pattern, int64_t count) {
    Array keys_array;
    if (!is_connected()) return keys_array;
    try {
        long long cursor = 0;
        
        while (true) {
            std::vector<std::string> keys;
            cursor = _redis_client->scan(cursor, pattern.utf8().get_data(), count, std::back_inserter(keys));

            for (const auto& key : keys) {
                String gd_key;
                keys_array.push_back(gd_key.utf8(key.c_str(), key.length()));
            }
            if (cursor == 0) {
                break; // Scansione completata
            }
        }
    } catch (const sw::redis::Error &e) {
        String error_message = "[Redis C++] Errore in scan_keys: ";
        error_message += e.what();
        UtilityFunctions::push_error(error_message);
    }
    return keys_array;
}

bool RedisClient::is_in_transaction() {
    return _is_in_transaction;
}

bool RedisClient::begin_transaction(const Array& keys_to_watch) {
    if (!is_connected()) {
        UtilityFunctions::push_error("[Redis C++] Impossibile iniziare la transazione: non connesso.");
        return false;
    }
    if (is_in_transaction()) {
        UtilityFunctions::push_error("[Redis C++] Impossibile iniziare la transazione: un'altra è già in corso.");
        return false;
    }

    try {
        // 1. Esegui WATCH se ci sono chiavi da osservare
        if (!keys_to_watch.is_empty()) {
            std::vector<std::string> watched_keys_vec;
            for (int i = 0; i < keys_to_watch.size(); ++i) {
                watched_keys_vec.push_back(String(keys_to_watch[i]).utf8().get_data());
            }
            _redis_client->watch(watched_keys_vec.begin(), watched_keys_vec.end());
        }

        // 2. Crea l'oggetto transazione
        _transaction = std::make_unique<sw::redis::Transaction>(_redis_client->transaction(true)); // Usiamo la modalità pipeline
        _is_in_transaction = true;
        return true;

    } catch (const sw::redis::Error &e) {
        String error_message = "[Redis C++] Errore in begin_transaction: ";
        error_message += e.what();
        UtilityFunctions::push_error(error_message);
        return false;
    }
}

void RedisClient::discard_transaction() {
    if (!is_in_transaction()) return;
    
    try {
        // Invia esplicitamente DISCARD al server.
        // Questo pulisce anche lo stato lato server e fa UNWATCH.
        _transaction->discard();
        UtilityFunctions::print("[Redis C++] Transazione annullata.");
    } catch (const sw::redis::Error &e) {
        String error_message = "[Redis C++] Errore in discard_transaction: ";
        error_message += e.what();
        UtilityFunctions::push_error(error_message);
    }

    // Pulisce lo stato locale in ogni caso.
    clear_transaction();

    // redis-plus-plus chiama UNWATCH automaticamente quando la transazione viene distrutta
    UtilityFunctions::print("[Redis C++] Transazione annullata.");
}

void RedisClient::clear_transaction() {
    _transaction.reset();
    _is_in_transaction = false;
}

Dictionary RedisClient::commit_transaction() {
    Dictionary result;
    if (!is_in_transaction()) {
        UtilityFunctions::push_error("[Redis C++] Impossibile fare commit: nessuna transazione in corso.");
        result["success"] = false;
        result["error"] = "Nessuna transazione in corso.";
        return result;
    }

    try {

        // Esegui la transazione
        auto replies = _transaction->exec();

        // Se exec() non lancia un'eccezione, la transazione è stata eseguita.
        result["success"] = true;
        Array replies_array;
        // Qui potremmo convertire le replies in Variant, ma è complesso.
        // Per ora, ci basta sapere che è andata a buon fine.
        replies_array.push_back("Transaction executed successfully.");
        result["replies"] = replies_array;

    } catch (const sw::redis::WatchError &e) {
        // WATCH ha fallito, la transazione è stata annullata dal server.
        result["success"] = false;
        result["error"] = "Transaction aborted due to watched key modification.";
        UtilityFunctions::print("[Redis C++] Transaction aborted: ", e.what());

    } catch (const sw::redis::Error &e) {
        result["success"] = false;
        String error_message = "[Redis C++] Errore in commit_transaction: ";
        error_message += e.what();
        result["error"] = error_message;
        UtilityFunctions::push_error(error_message);
    }
    
    // Pulisci lo stato in ogni caso
    clear_transaction();

    return result;
}

bool RedisClient::del_keys(const Array& keys) {
    if (!is_connected() || keys.is_empty()) return false;

    try {
        // Converti l'Array di Godot in un contenitore C++
        std::vector<std::string> keys_vec;
        keys_vec.reserve(keys.size());
        for (int i = 0; i < keys.size(); ++i) {
            keys_vec.push_back(String(keys[i]).utf8().get_data());
        }

        if (is_in_transaction()) {
            // Modalità Transazione
            _transaction->del(keys_vec.begin(), keys_vec.end());
        } else {
            // Modalità Normale
            _redis_client->del(keys_vec.begin(), keys_vec.end());
        }
        return true;
    } catch (const sw::redis::Error &e) {
        String error_message = "[Redis C++] Errore in del_keys: ";
        error_message += e.what();
        UtilityFunctions::push_error(error_message);
        return false;
    }
}