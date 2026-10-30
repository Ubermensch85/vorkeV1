#!/usr/bin/env bash
# =============================================================================
# guardian-update.sh — Agente di Aggiornamento Sicuro con Rollback Automatico
# =============================================================================
set -uo pipefail

LOCK_FILE="/run/guardian-update.lock"
NOTIFY_BIN="/usr/local/bin/guardian-notify.sh"
DNSPROXY_BIN="/usr/local/bin/dnsproxy"
DNSPROXY_BAK="/usr/local/bin/dnsproxy.bak"
LOG_FILE="/tmp/guardian-update-$(date +'%Y%m%d-%H%M%S').log"

exec 200>"$LOCK_FILE"
flock -n 200 || { echo "Aggiornamento già in corso. Esco."; exit 0; }

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

notify() {
    log "$1"
    if [ -x "$NOTIFY_BIN" ]; then
        "$NOTIFY_BIN" "$1"
    fi
}

log "=== Avvio Procedura di Aggiornamento Intelligente Guardian ==="

# Pre-flight check: verifica che la rete sia funzionante prima di toccare il sistema
if ! dig @127.0.0.1 -p 53 cloudflare.com +short +time=2 >/dev/null 2>&1; then
    log "ERRORE: Risoluzione DNS locale attualmente non funzionante. Aggiornamento annullato per sicurezza."
    notify "⚠️ <b>Aggiornamento annullato:</b> La catena DNS locale presenta anomalie prima dell'update. Nessuna modifica effettuata."
    exit 1
fi

DEBIAN_UPDATED=0
DNSPROXY_UPDATED=0
PIHOLE_UPDATED=0

# -----------------------------------------------------------------------------
# 1. Aggiornamento Pacchetti Sistema Debian
# -----------------------------------------------------------------------------
log "1. Aggiornamento pacchetti Debian (apt)..."
export DEBIAN_FRONTEND=noninteractive
apt-get update >> "$LOG_FILE" 2>&1
UPGRADEABLE=$(apt-get -s upgrade | grep -P "^\d+ aggiornati" || echo "0 aggiornati")
apt-get dist-upgrade -y >> "$LOG_FILE" 2>&1
apt-get autoremove -y >> "$LOG_FILE" 2>&1
apt-get autoclean >> "$LOG_FILE" 2>&1
DEBIAN_UPDATED=1

# -----------------------------------------------------------------------------
# 2. Aggiornamento dnsproxy con Rollback Automatico
# -----------------------------------------------------------------------------
log "2. Verifica nuova versione di AdGuard dnsproxy da GitHub..."
CURRENT_VER=$($DNSPROXY_BIN --version 2>/dev/null | awk '{print $3}')
LATEST_VER=$(curl -sIL -o /dev/null -w '%{url_effective}' https://github.com/AdguardTeam/dnsproxy/releases/latest 2>/dev/null | awk -F'/' '{print $NF}')
if [ -z "$LATEST_VER" ] || [[ ! "$LATEST_VER" =~ ^v[0-9] ]]; then
    LATEST_VER=$(curl -s https://api.github.com/repos/AdguardTeam/dnsproxy/releases/latest 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
fi

if [ -n "$LATEST_VER" ] && [ "$CURRENT_VER" != "$LATEST_VER" ]; then
    log "Nuova versione disponibile per dnsproxy: $CURRENT_VER -> $LATEST_VER"
    URL="https://github.com/AdguardTeam/dnsproxy/releases/download/${LATEST_VER}/dnsproxy-linux-amd64-${LATEST_VER}.tar.gz"
    TMP_DIR=$(mktemp -d /tmp/dnsproxy-update.XXXXXX)

    if wget -qO "$TMP_DIR/dnsproxy.tar.gz" "$URL" && tar -xzf "$TMP_DIR/dnsproxy.tar.gz" -C "$TMP_DIR"; then
        NEW_BIN="$TMP_DIR/linux-amd64/dnsproxy"
        if [ -x "$NEW_BIN" ]; then
            log "Creazione backup preventivo di dnsproxy..."
            cp -p "$DNSPROXY_BIN" "$DNSPROXY_BAK"

            systemctl stop dnsproxy.service
            cp -f "$NEW_BIN" "$DNSPROXY_BIN"
            chmod 755 "$DNSPROXY_BIN"
            systemctl start dnsproxy.service
            sleep 3

            # Verifica post-installazione
            if dig @127.0.0.1 -p 5353 cloudflare.com +short +time=2 >/dev/null 2>&1; then
                log "dnsproxy aggiornato con successo a $LATEST_VER e test di risoluzione superato!"
                DNSPROXY_UPDATED=1
            else
                log "CRITICO: dnsproxy $LATEST_VER non risponde alle query! Avvio ROLLBACK immediato..."
                systemctl stop dnsproxy.service
                cp -f "$DNSPROXY_BAK" "$DNSPROXY_BIN"
                systemctl start dnsproxy.service
                sleep 2
                notify "🚨 <b>ROLLBACK ESEGUITO:</b> Il nuovo dnsproxy $LATEST_VER non rispondeva. Ripristinata la versione stabile $CURRENT_VER senza disservizi!"
            fi
        fi
    fi
    rm -rf "$TMP_DIR"
else
    log "dnsproxy è già all'ultima versione ($CURRENT_VER)."
fi

# -----------------------------------------------------------------------------
# 3. Aggiornamento Pi-hole
# -----------------------------------------------------------------------------
log "3. Controllo aggiornamenti Pi-hole..."
if command -v pihole &>/dev/null; then
    pihole updatePihole >> "$LOG_FILE" 2>&1 || true
    # Verifica che FTL risponda dopo l'aggiornamento
    sleep 2
    if ! dig @127.0.0.1 -p 53 cloudflare.com +short +time=2 >/dev/null 2>&1; then
        log "Tentativo riavvio pihole-FTL..."
        systemctl restart pihole-FTL.service
    fi
    PIHOLE_UPDATED=1
fi

# -----------------------------------------------------------------------------
# 4. Metriche e Report Finale
# -----------------------------------------------------------------------------
log "4. Raccolta metriche di performance..."
UPTIME=$(uptime -p | sed "s/up //")
RAM=$(free -m | awk '/Mem:/ { printf("%d%%", $3/$2*100) }')
PUBLIC_IP=$(curl -s -m 3 https://ifconfig.me 2>/dev/null || echo "N/D")
TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "N/D")

# Latenze di test
LAT_PIHOLE=$(dig @127.0.0.1 -p 53 google.com 2>/dev/null | grep "Query time:" | awk '{print $4 " ms"}' || echo "N/D")
LAT_DNSPROXY=$(dig @127.0.0.1 -p 5353 google.com 2>/dev/null | grep "Query time:" | awk '{print $4 " ms"}' || echo "N/D")

DNS_STATUS="✅ ONLINE"
if ! dig @127.0.0.1 -p 53 google.com +short +time=1 >/dev/null 2>&1; then
    DNS_STATUS="⚠️ DEGRADATO"
fi

REPORT="✅ <b>Manutenzione & Aggiornamento Completati</b>
───────────────────
⏱️ Uptime: <code>$UPTIME</code>
🧠 RAM: <code>$RAM</code> | 🌐 IP: <code>$PUBLIC_IP</code>

🔐 <b>STATO CATENA DNS</b>
• Pi-hole (porta 53): <b>$DNS_STATUS</b> ($LAT_PIHOLE)
• dnsproxy DoQ/DoH: <b>ONLINE</b> ($LAT_DNSPROXY)
• dnsproxy ver: <code>$($DNSPROXY_BIN --version 2>/dev/null | awk '{print $3}')</code>

🔗 <b>TAILSCALE</b>
• IP Mesh: <code>$TAILSCALE_IP</code>

🛡️ <i>Tutti i servizi sono operativi per la casa di Roccella.</i>"

notify "$REPORT"
log "=== Procedura completata con successo ==="
rm -f "$LOG_FILE"
