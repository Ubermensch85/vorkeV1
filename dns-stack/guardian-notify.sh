#!/usr/bin/env bash
# =============================================================================
# guardian-notify.sh — Modulo di Notifica Telegram per Vorke Roccella
# =============================================================================

SERVER_TAG="🏠 <b>[Vorke Roccella - Genitori]</b>"
RAW_MESSAGE="$1"

if [ -z "$RAW_MESSAGE" ]; then
    echo "Errore: Messaggio vuoto." >&2
    exit 1
fi

FULL_MESSAGE="${SERVER_TAG}
${RAW_MESSAGE}"

# 1. Controllo token in file di configurazione utente o di sistema
for conf in "/etc/dns-guardian/telegram.conf" "/home/ubermensch/.config/dns-guardian/telegram.conf"; do
    if [ -f "$conf" ]; then
        # shellcheck source=/dev/null
        source "$conf"
        break
    fi
done

if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ]; then
    curl -s -m 10 -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d chat_id="${TELEGRAM_CHAT_ID}" \
        -d text="${FULL_MESSAGE}" \
        -d parse_mode="HTML" > /dev/null 2>&1
    exit 0
fi

# 2. Fallback a telegram-send locale se presente
if [ -x "/home/ubermensch/BotServer_Public/telegram-send" ]; then
    /home/ubermensch/BotServer_Public/telegram-send "$FULL_MESSAGE" 2>/dev/null && exit 0
fi

# 3. Fallback di sistema
if [ -x "/usr/local/bin/telegram-send" ]; then
    /usr/local/bin/telegram-send "$FULL_MESSAGE" 2>/dev/null && exit 0
fi

# Log su syslog/journal se non è stato possibile inviare su Telegram
logger -t dns-guardian "$RAW_MESSAGE"
