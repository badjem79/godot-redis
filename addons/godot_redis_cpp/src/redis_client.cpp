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

    // --- FINE REGISTRAZIONE PROPRIETÀ ---

    // Metodi esposti a GDScript
    ClassDB::bind_method(D_METHOD("connect_to_redis"), &RedisClient::connect_to_redis);

    ClassDB::bind_method(D_METHOD("set_value", "key", "value"), &RedisClient::set_value);
    ClassDB::bind_method(D_METHOD("get_value", "key"), &RedisClient::get_value);
    ClassDB::bind_method(D_METHOD("increment_value", "key", "amount"), &RedisClient::increment_value, DEFVAL(1));

    // HASHES
    ClassDB::bind_method(D_METHOD("hset_value", "key", "field", "value"), &RedisClient::hset_value);
    ClassDB::bind_method(D_METHOD("hget_value", "key", "field"), &RedisClient::hget_value);
    ClassDB::bind_method(D_METHOD("hset_multiple_values", "key", "data"), &RedisClient::hset_multiple_values);
    ClassDB::bind_method(D_METHOD("hget_all_values", "key"), &RedisClient::hget_all_values);

    // SCAN
    ClassDB::bind_method(D_METHOD("scan_keys", "pattern", "count"), &RedisClient::scan_keys, DEFVAL(10));
    ClassDB::bind_method(D_METHOD("is_connected"), &RedisClient::is_connected);
    
    // --- BIND DEI METODI DI TRANSAZIONE ---
    ClassDB::bind_method(D_METHOD("begin_transaction", "keys_to_watch"), &RedisClient::begin_transaction, DEFVAL(Array()));
    ClassDB::bind_method(D_METHOD("commit_transaction"), &RedisClient::commit_transaction);
    ClassDB::bind_method(D_METHOD("discard_transaction"), &RedisClient::discard_transaction);
    ClassDB::bind_method(D_METHOD("is_in_transaction"), &RedisClient::is_in_transaction);

    // Segnale per notificare il risultato della connessione
    ADD_SIGNAL(MethodInfo("connection_status_changed", PropertyInfo(Variant::BOOL, "is_connected"), PropertyInfo(Variant::STRING, "message")));

    // Metodo privato chiamato tramite call_deferred
    ClassDB::bind_method(D_METHOD("_connection_finished", "success", "message"), &RedisClient::_connection_finished);
}

void RedisClient::_ready() {
    UtilityFunctions::print("[Redis C++] Inizializzazione, tentativo di connessione...");
    connect_to_redis();
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
        return val ? String(val->c_str()) : String(); // Restituisce stringa vuota se non esiste
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
        return val ? String(val->c_str()) : String(); // Restituisce stringa vuota se non trovato
    } catch (const sw::redis::Error &e) {
        String error_message = "[Redis C++] Errore in hget_value: ";
        error_message += e.what();
        UtilityFunctions::push_error(error_message);
        return "";
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
        _redis_client->hgetall(key.utf8().get_data(), std::inserter(items, items.begin()));
        
        for (const auto& pair : items) {
            result[String(pair.first.c_str())] = String(pair.second.c_str());
        }
    } catch (const sw::redis::Error &e) {
        String error_message = "[Redis C++] Errore in hget_all_values: ";
        error_message += e.what();
        UtilityFunctions::push_error(error_message);
    }
    return result;
}

// SCAN: Scansiona le chiavi in modo sicuro
Array RedisClient::scan_keys(const String& pattern, int64_t count) {
    Array keys_array;
    if (!is_connected()) return keys_array;
    try {
        long long cursor = 0;
        std::vector<std::string> keys;
        
        // redis-plus-plus gestisce il ciclo di scan internamente, molto comodo!
        // Usiamo un inseritore per popolare direttamente il nostro vettore.
        _redis_client->scan(cursor, pattern.utf8().get_data(), count, std::back_inserter(keys));

        for (const auto& key : keys) {
            keys_array.push_back(String(key.c_str()));
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