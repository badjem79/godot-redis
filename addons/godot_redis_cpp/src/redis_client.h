// src/redis_client.h
#ifndef REDIS_CLIENT_H
#define REDIS_CLIENT_H

#include <godot_cpp/classes/node.hpp>
#include <sw/redis++/redis.h>
#include <sw/redis++/queued_redis.h>
#include <sw/redis++/transaction.h> // Includiamo la definizione completa per Transaction
#include <memory>
#include <thread>

namespace godot {
    class RedisClient : public Node {
        GDCLASS(RedisClient, Node)

    private:
        std::unique_ptr<sw::redis::Redis> _redis_client;

        std::unique_ptr<sw::redis::Transaction> _transaction;

        bool _is_in_transaction = false;

        String host = "127.0.0.1";
        int port = 6379;

    protected:
        static void _bind_methods();

    public:
        RedisClient();
        ~RedisClient();

        void _ready() override;
        void _exit_tree() override;

        // --- NUOVI METODI GETTER E SETTER ---
        void set_host(const String& p_host);
        String get_host() const;

        void set_port(int p_port);
        int get_port() const;
        // --- FINE NUOVI METODI ---

        void connect_to_redis();

        // chiavi valori normali
        bool set_value(const String& key, const String& value);
        String get_value(const String& key);
        int64_t increment_value(const String& key, int64_t amount = 1);

        // HASHES
        bool hset_value(const String& key, const String& field, const String& value);
        String hget_value(const String& key, const String& field);
        bool hset_multiple_values(const String& key, const Dictionary& data);
        Dictionary hget_all_values(const String& key);

        // --- METODI DI CONTROLLO TRANSAZIONE ---
        bool begin_transaction(const Array& keys_to_watch);
        Dictionary commit_transaction();
        void discard_transaction();
        void clear_transaction();
        bool is_in_transaction();
        // --- FINE METODI DI CONTROLLO ---
        
        // SCAN
        Array scan_keys(const String& pattern, int64_t count = 10);
        
        bool is_connected();

        void _connection_finished(bool success, const String& message);
    };
}
#endif // REDIS_CLIENT_H
