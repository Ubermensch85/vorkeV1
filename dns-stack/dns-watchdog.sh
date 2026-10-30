#!/usr/bin/env bash
# =============================================================================
# dns-watchdog.sh — Watchdog di Auto-Guarigione per Vorke Roccella
# =============================================================================
set -u

RUN_DIR="/run/dns-guardian"
mkdir -p "$RUN_DIR"
STATE_FILE="$RUN_DIR/watchdog_state"
NOTIFY_BIN="/usr/local/bin/guardian-notify.sh"

log() {
    logger -t dns-watchdog "$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

notify() {
    log "$1"
    if [ -x "$NOTIFY_BIN" ]; then
        "$NOTIFY_BIN" "$1"
    fi
}

check_dns() {
    local port="$1"
    local domain="cloudflare.com"
    dig @"127.0.0.1" -p "$port" "$domain" +time=2 +tries=1 +short 2>/dev/null | grep -E '^[0-9.]+$' >/dev/null
    return $?
}

check_gateway() {
    # Controllo raggiungibilità del router TP-Link (192.168.0.1)
    ping -c 1 -W 1 192.168.0.1 >/dev/null 2>&1
    return $?
}

check_wan() {
    # Controllo raggiungibilità WAN
    ping -c 1 -W 2 1.0.0.2 >/dev/null 2>&1 || ping -c 1 -W 2 9.9.9.9 >/dev/null 2>&1
    return $?
}

# 1. Controllo dnsproxy (Porta 5353)
if ! check_dns 5353; then
    log "ATTENZIONE: dnsproxy (porta 5353) non risponde."
    
    if ! check_gateway; then
        log "LAN/Gateway 192.168.0.1 non raggiungibile. Possibile riavvio del router TP-Link. Nessun riavvio forzato."
        exit 0
    fi

    log "Riavvio di dnsproxy.service in corso..."
    systemctl restart dnsproxy.service
    sleep 3

    if check_dns 5353; then
        notify "🔄 <b>dnsproxy riavviato e ripristinato</b> con successo dopo un mancato riscontro. Risoluzione DoQ/DoH attiva."
    else
        if ! check_wan; then
            log "Connessione WAN/Fibra assente (ONT non allineato). dnsproxy in attesa di connettività esterna."
        else
            notify "⚠️ <b>ALLERTA CRITICA:</b> dnsproxy non risponde neanche dopo il riavvio manuale! Verificare connettività remota."
        fi
    fi
fi

# 2. Controllo Pi-hole FTL (Porta 53)
if ! check_dns 53; then
    log "ATTENZIONE: Pi-hole FTL (porta 53) non risponde."
    log "Riavvio di pihole-FTL.service in corso..."
    systemctl restart pihole-FTL.service
    sleep 3

    if check_dns 53; then
        notify "🔄 <b>Pi-hole FTL riavviato e ripristinato</b> con successo. Blocco annunci e routing DNS per i dispositivi di casa attivi."
    else
        notify "🚨 <b>ALLERTA CRITICA:</b> Pi-hole FTL (porta 53) continua a non rispondere dopo il riavvio!"
    fi
fi

# 3. Controllo Tailscale
if ! tailscale status >/dev/null 2>&1; then
    log "ATTENZIONE: Demone Tailscale disconnesso o non attivo."
    systemctl restart tailscaled.service
    sleep 3
    if tailscale status >/dev/null 2>&1; then
        notify "🔗 <b>Tailscale ripristinato:</b> Nodo Vorke nuovamente raggiungibile via mesh da Perugia."
    fi
fi
