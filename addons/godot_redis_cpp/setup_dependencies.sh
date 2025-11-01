#!/bin/bash
# Questo script configura le dipendenze manuali necessarie per compilare l'addon.
# Eseguilo dalla radice dell'addon (addons/godot_redis_cpp/).

set -e # Esce immediatamente se un comando fallisce

echo "Configuring redis-plus-plus submodule..."

# Naviga nella cartella di redis-plus-plus
cd thirdparty/redis-plus-plus/src/sw/redis++/

# --- 1. Create Symbolic Links ---
echo "Creating symbolic links for C++17, no-TLS, and std::future..."
ln -sf cxx17/sw/redis++/cxx_utils.h .
ln -sf no_tls/sw/redis++/tls.h .
ln -sf future/std/sw/redis++/async_utils.h .
# L'opzione -f (force) sovrascrive i link se esistono già.
# L'opzione -s crea un link simbolico.

# --- 2. Create hiredis_features.h ---
echo "Creating hiredis_features.h..."
# Usiamo 'cat <<EOF' per scrivere un blocco di testo in un file.
cat > hiredis_features.h <<EOF
#ifndef SW_REDIS_HIREDIS_FEATURES_H
#define SW_REDIS_HIREDIS_FEATURES_H

#define HIREDIS_WITH_ASYNC_DISCONNECT
#define HIREDIS_WITH_PUSH_CALLBACK
#define HIREDIS_WITH_PRIVDATA
#define HIREDIS_WITH_SDS_HEADER
#define HIREDIS_WITH_PUSH_PRIVDATA

#endif // SW_REDIS_HIREDIS_FEATURES_H
EOF

echo "redis-plus-plus configured successfully."
cd ../../../../.. # Torna alla radice dell'addon

echo "Dependency setup complete."