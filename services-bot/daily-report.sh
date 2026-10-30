#!/bin/bash
# =============================================================================
# daily-report.sh — Report di stato giornaliero per Vorke
# =============================================================================

# CONFIGURAZIONE CREDENZIALI
TR_AUTH="${TRANSMISSION_AUTH:-transmission:transmission}" # Utente:Password configurabile
HOST=$(hostname)

# DATI
UPDATES=$(apt list --upgradable 2>/dev/null | grep "/" | wc -l)
DISK=$(df -h /home 2>/dev/null | awk 'NR==2 {print $5}')
ADS=$(pihole -c -j 2>/dev/null | grep "ads_blocked_today" | grep -oE '[0-9]+' | head -1)
ADS=${ADS:-0}

# STATO SERVIZI (Funzione grafica)
status_icon() {
    if systemctl is-active --quiet "$1" 2>/dev/null; then
        echo "🟢 On"
    else
        echo "🔴 <b>OFF</b>"
    fi
}

S_PIHOLE=$(status_icon pihole-FTL)
S_DNSPROXY=$(status_icon dnsproxy)
S_TAIL=$(status_icon tailscaled)

# TORRENT
if command -v transmission-remote &> /dev/null; then
    DL=$(transmission-remote -n "$TR_AUTH" -l 2>/dev/null | grep "Downloading" | wc -l)
    UP=$(transmission-remote -n "$TR_AUTH" -l 2>/dev/null | grep "Seeding" | wc -l)
else
    DL="?"
    UP="?"
fi

# --- OUTPUT FORMATTATO ---
echo "📊 <b>SYSTEM STATUS: $HOST</b>"
echo ""
echo "💾 <b>Risorse</b>"
echo "├─ 📦 Updates: <b>$UPDATES</b>"
echo "└─ 💿 Home:    <b>$DISK</b>"
echo ""
echo "🛡️ <b>Sicurezza & Rete</b>"
echo "├─ Pi-hole:    $S_PIHOLE ($ADS ads bloccati)"
echo "├─ DNSProxy:   $S_DNSPROXY"
echo "└─ Tailscale:  $S_TAIL"
echo ""
echo "⬇️ <b>Transmission</b>"
echo "└─ DL: <b>$DL</b>  |  UP: <b>$UP</b>"
