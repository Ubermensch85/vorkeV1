#!/usr/bin/env bash
# =============================================================================
# set-telegram.sh — Configura e verifica il Bot Telegram per Vorke Roccella
# =============================================================================
set -e

TOKEN="${1:-}"
CHAT_ID="${2:-}"

if [ -z "$TOKEN" ] || [ -z "$CHAT_ID" ]; then
    echo "Uso: $0 <BOT_TOKEN> <CHAT_ID>"
    echo "Esempio: $0 123456789:ABCdefGhIjkLmNoPqRsTuVwXyZ 132696855"
    exit 1
fi

echo "🔍 Verifica validità del token con Telegram..."
RES=$(curl -s "https://api.telegram.org/bot${TOKEN}/getMe" 2>/dev/null || true)

if echo "$RES" | grep -q '"ok":true'; then
    BOT_NAME=$(echo "$RES" | grep -o '"username":"[^"]*' | cut -d'"' -f4)
    echo "✅ Token valido! Bot associato: @$BOT_NAME"
else
    echo "❌ Errore: Il token inserito non è valido (Telegram API ha risposto non autorizzato)."
    echo "   Risposta: $RES"
    exit 1
fi

echo "📤 Invio messaggio di test a CHAT_ID: $CHAT_ID..."
MSG="🏠 <b>[Vorke Roccella - Genitori]</b>%0A🎉 <b>Connessione Telegram configurata con successo!</b>%0A🛡️ DNS Guardian pronto a inviare report e notifiche."
SEND_RES=$(curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
    -d chat_id="${CHAT_ID}" \
    -d text="${MSG}" \
    -d parse_mode="HTML" 2>/dev/null || true)

if echo "$SEND_RES" | grep -q '"ok":true'; then
    echo "✅ Messaggio di test inviato e ricevuto con successo!"
else
    echo "⚠️ Attenzione: Impossibile inviare il messaggio alla chat $CHAT_ID."
    echo "   Hai già avviato la chat con il bot premendo /start?"
    echo "   Risposta: $SEND_RES"
    exit 1
fi

# Salvataggio nella configurazione
CONFIG_DIR="/etc/dns-guardian"
if [ "$EUID" -eq 0 ]; then
    mkdir -p "$CONFIG_DIR"
    cat << EOF > "$CONFIG_DIR/telegram.conf"
TELEGRAM_BOT_TOKEN="$TOKEN"
TELEGRAM_CHAT_ID="$CHAT_ID"
EOF
    chmod 600 "$CONFIG_DIR/telegram.conf"
    echo "💾 Configurazione salvata in $CONFIG_DIR/telegram.conf"
else
    echo "💾 Salvataggio configurazione tramite sudo..."
    sudo mkdir -p "$CONFIG_DIR"
    sudo bash -c "cat << EOF > '$CONFIG_DIR/telegram.conf'
TELEGRAM_BOT_TOKEN='$TOKEN'
TELEGRAM_CHAT_ID='$CHAT_ID'
EOF"
    sudo chmod 600 "$CONFIG_DIR/telegram.conf"
    echo "💾 Configurazione salvata con successo!"
fi

echo "🎯 Fatto! Ora tutti i report e le allerte del server dei tuoi genitori arriveranno sul tuo Telegram."
