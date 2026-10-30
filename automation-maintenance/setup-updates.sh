#!/bin/bash
# Questo script deve essere eseguito con privilegi root: sudo ./setup-updates.sh

if [ "$EUID" -ne 0 ]; then
  echo "Per favore, esegui questo script come root (con sudo)."
  exit 1
fi

echo "=== Configurazione degli Script di Aggiornamento ==="

# 1. Creazione di /usr/local/bin/update-system.sh
cat << 'EOF' > /usr/local/bin/update-system.sh
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive

echo "--- Aggiornamento dei pacchetti di sistema ---"
apt-get update && apt-get upgrade -y

echo "--- Pulizia dei pacchetti inutilizzati ---"
apt-get autoremove -y && apt-get autoclean

echo "--- Aggiornamento di Pi-hole ---"
if command -v pihole &>/dev/null; then
    pihole updatePihole
else
    echo "Pi-hole non è installato su questo sistema."
fi
EOF
chmod 755 /usr/local/bin/update-system.sh
chown root:root /usr/local/bin/update-system.sh
echo "[OK] Creato /usr/local/bin/update-system.sh"

# 2. Creazione di /usr/local/bin/update-dnsproxy.sh (migrato da /home/ubermensch/update-dnsproxy.sh)
cat << 'EOF' > /usr/local/bin/update-dnsproxy.sh
#!/bin/bash
# Percorso binario
BIN_PATH="/usr/local/bin/dnsproxy"
# Versione attuale
CURRENT_VER=$($BIN_PATH --version 2>/dev/null | awk '{print $3}')
# Ultima versione su GitHub
LATEST_VER=$(curl -s https://api.github.com/repos/AdguardTeam/dnsproxy/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

if [ -z "$LATEST_VER" ]; then
    echo "Errore nel recuperare l'ultima versione di dnsproxy da GitHub."
    exit 1
fi

if [ "$CURRENT_VER" == "$LATEST_VER" ]; then
    echo "dnsproxy è già aggiornato ($CURRENT_VER)."
    exit 0
fi

echo "Aggiornamento disponibile: $CURRENT_VER -> $LATEST_VER"
URL="https://github.com/AdguardTeam/dnsproxy/releases/download/${LATEST_VER}/dnsproxy-linux-amd64-${LATEST_VER}.tar.gz"

cd /tmp && wget -qO dnsproxy.tar.gz "$URL" && \
tar -xzf dnsproxy.tar.gz && \
systemctl stop dnsproxy && \
mv linux-amd64/dnsproxy $BIN_PATH && \
chmod +x $BIN_PATH && \
systemctl start dnsproxy && \
echo "Aggiornamento dnsproxy completato con successo!"
EOF
chmod 755 /usr/local/bin/update-dnsproxy.sh
chown root:root /usr/local/bin/update-dnsproxy.sh
echo "[OK] Creato /usr/local/bin/update-dnsproxy.sh"

# 3. Configurazione di sudoers.d per permettere l'esecuzione senza password
SUDOERS_FILE="/etc/sudoers.d/ubermensch-update"
cat << 'EOF' > "$SUDOERS_FILE"
# Permette all'utente ubermensch di eseguire gli script di aggiornamento senza inserire la password
ubermensch ALL=(root) NOPASSWD: /usr/local/bin/update-system.sh, /usr/local/bin/update-dnsproxy.sh
EOF
chmod 0440 "$SUDOERS_FILE"
chown root:root "$SUDOERS_FILE"
echo "[OK] Configurato sudoers in $SUDOERS_FILE"

echo "=== Configurazione completata con successo! ==="
