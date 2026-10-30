#!/bin/bash
export DEBIAN_FRONTEND=noninteractive

echo "--- Aggiornamento dei pacchetti di sistema ---"
apt-get update && apt-get dist-upgrade -y

echo "--- Pulizia dei pacchetti inutilizzati ---"
apt-get autoremove -y && apt-get autoclean

echo "--- Aggiornamento di Pi-hole ---"
if command -v pihole &>/dev/null; then
    pihole updatePihole
else
    echo "Pi-hole non è installato su questo sistema."
fi
