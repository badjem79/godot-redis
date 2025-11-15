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
        bool hdel_values(const String& key, const Array& fields);
        bool hset_multiple_values(const String& key, const Dictionary& data);
        Dictionary hget_all_values(const String& key);

        // SETs
        bool sadd_values(const String& key, const Array& members);
        bool srem_values(const String& key, const Array& members);
        Array smembers_keys(const String& key);
        int64_t scard_count(const String& key);
        bool sismember(const String& key, const String& member);

        // --- METODI PER I SORTED SET (ZSET) ---
        bool zadd_values(const String& key, const Dictionary& members_scores);
        bool zrem_values(const String& key, const Array& members);
        Variant zrange_values(const String& key, int64_t start, int64_t stop, bool with_scores = false);
        Variant zrevrange_values(const String& key, int64_t start, int64_t stop, bool with_scores = false);

        // --- METODI DI CONTROLLO TRANSAZIONE ---
        bool begin_transaction(const Array& keys_to_watch);
        Dictionary commit_transaction();
        void discard_transaction();
        void clear_transaction();
        bool is_in_transaction();
        // --- FINE METODI DI CONTROLLO ---
        
        // --- METODO PER DEL ---
        bool del_keys(const Array& keys);

        // SCAN
        Array scan_keys(const String& pattern, int64_t count = 10);
        
        bool is_connected();

        void _connection_finished(bool success, const String& message);
    };
}
#endif // REDIS_CLIENT_H
