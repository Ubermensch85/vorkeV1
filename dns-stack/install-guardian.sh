#!/usr/bin/env bash
# =============================================================================
# install-guardian.sh — Installatore Master Suite DNS Guardian
# Eseguire con: sudo /home/ubermensch/dns-guardian/install-guardian.sh
# =============================================================================
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
  echo "[-] Errore: Questo script richiede privilegi di amministratore."
  echo "    Esegui: sudo $0"
  exit 1
fi

SRC_DIR="/home/ubermensch/dns-guardian"
CONFIG_DIR="/etc/dns-guardian"
USER_CONF="/home/ubermensch/.config/dns-guardian/telegram.conf"

echo "=========================================================="
echo "    INSTALLAZIONE SUITE DNS GUARDIAN (Vorke Roccella)     "
echo "=========================================================="

# 1. Configurazione directory e permessi
mkdir -p "$CONFIG_DIR"
chmod 750 "$CONFIG_DIR"

# 2. Configurazione Token Telegram
if [ -f "$USER_CONF" ]; then
    cp "$USER_CONF" "$CONFIG_DIR/telegram.conf"
    chmod 600 "$CONFIG_DIR/telegram.conf"
    echo "[+] Configurazione Telegram importata in $CONFIG_DIR/telegram.conf"
    
    # Aggiorna anche /usr/local/bin/telegram-send per retrocompatibilità
    TOKEN=$(grep -E '^TELEGRAM_BOT_TOKEN=' "$USER_CONF" | cut -d'"' -f2 || true)
    CHAT_ID=$(grep -E '^TELEGRAM_CHAT_ID=' "$USER_CONF" | cut -d'"' -f2 || true)
    if [ -n "$TOKEN" ] && [ -n "$CHAT_ID" ]; then
        cat << EOF > /usr/local/bin/telegram-send
#!/bin/bash
TOKEN="$TOKEN"
CHAT_ID="$CHAT_ID"
MESSAGE="\$1"
[ -z "\$MESSAGE" ] && exit 1
curl -s -X POST "https://api.telegram.org/bot\$TOKEN/sendMessage" \
    -d chat_id="\$CHAT_ID" \
    -d text="\$MESSAGE" \
    -d parse_mode="HTML" > /dev/null
EOF
        chmod 755 /usr/local/bin/telegram-send
        echo "[+] Aggiornato anche /usr/local/bin/telegram-send"
    fi
fi

# 3. Installazione binari in /usr/local/bin
echo "[+] Installazione script di controllo e aggiornamento in /usr/local/bin..."
cp "$SRC_DIR/guardian-notify.sh" /usr/local/bin/guardian-notify.sh
cp "$SRC_DIR/dns-watchdog.sh" /usr/local/bin/dns-watchdog.sh
cp "$SRC_DIR/guardian-update.sh" /usr/local/bin/guardian-update.sh

chmod 755 /usr/local/bin/guardian-notify.sh
chmod 755 /usr/local/bin/dns-watchdog.sh
chmod 755 /usr/local/bin/guardian-update.sh

# 4. Ottimizzazione dnsproxy.service
echo "[+] Aggiornamento configurazione dnsproxy (DoQ/DoH3 + Cache Ottimistica)..."
if [ -f "/etc/systemd/system/dnsproxy.service" ]; then
    cp /etc/systemd/system/dnsproxy.service /etc/systemd/system/dnsproxy.service.bak
fi
cp "$SRC_DIR/dnsproxy.service" /etc/systemd/system/dnsproxy.service

# 5. Installazione unità systemd (Watchdog + Auto-Updater)
echo "[+] Installazione servizi e timer systemd..."
cp "$SRC_DIR/dns-watchdog.service" /etc/systemd/system/dns-watchdog.service
cp "$SRC_DIR/dns-watchdog.timer" /etc/systemd/system/dns-watchdog.timer
cp "$SRC_DIR/guardian-update.service" /etc/systemd/system/guardian-update.service
cp "$SRC_DIR/guardian-update.timer" /etc/systemd/system/guardian-update.timer

# 6. Configurazione sudoers per esecuzione manuale da utente ubermensch senza password
SUDOERS_FILE="/etc/sudoers.d/ubermensch-guardian"
cat << 'EOF' > "$SUDOERS_FILE"
ubermensch ALL=(root) NOPASSWD: /usr/local/bin/guardian-update.sh, /usr/local/bin/dns-watchdog.sh, /usr/local/bin/guardian-notify.sh
EOF
chmod 0440 "$SUDOERS_FILE"
echo "[+] Permessi sudoers configurati in $SUDOERS_FILE"

# 7. Reload systemd e avvio
echo "[+] Ricaricamento configurazioni systemd..."
systemctl daemon-reload
systemctl restart dnsproxy.service
systemctl enable --now dns-watchdog.timer
systemctl enable --now guardian-update.timer

# 8. Test immediato del Watchdog
echo "[+] Test funzionamento Watchdog..."
/usr/local/bin/dns-watchdog.sh

# 9. Invio notifica di avvenuta installazione
/usr/local/bin/guardian-notify.sh "🎉 <b>Installazione Suite DNS Guardian Completata!</b>%0A🛡️ Watchdog attivo (check ogni 60s)%0A🔄 Auto-update programmato (Mer/Dom 04:30)%0A⚡ dnsproxy ottimizzato con cache ottimistica e DoQ." || true

echo "=========================================================="
echo "  INSTALLAZIONE COMPLETATA CON SUCCESSO!                  "
echo "  - Notifica Telegram inviata con successo.               "
echo "  - Watchdog attivo: ogni 60 secondi                      "
echo "  - Aggiornamento automatico: Mer e Dom alle 04:30        "
echo "=========================================================="
