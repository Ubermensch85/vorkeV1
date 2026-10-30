#!/usr/bin/env bash
# =============================================================================
# UFW SETUP — ProDesk G3 600 | Debian (Versione aggiornata 2026)
# Interfaccia Ethernet: enp1s0 (rilevamento dinamico con fallback)
# Interfaccia Tailscale: tailscale0
# =============================================================================

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Esegui come root: sudo bash ufw-setup.sh"
    exit 1
fi

echo ""
echo "=========================================="
echo " UFW SETUP — ProDesk Debian"
echo "=========================================="
echo ""

# Rilevamento interfacce
ETH="${ETH:-$(ip route show default 2>/dev/null | awk '/default/ {print $5}' | head -n1)}"
ETH="${ETH:-enp1s0}"
TS="tailscale0"

echo "Interfaccia Ethernet principale: $ETH"
echo "Interfaccia Tailscale: $TS"
echo ""

# =============================================================================
# STEP 1 — Installazione ufw
# =============================================================================
echo "[1/8] Verifica ufw..."
if ! command -v ufw &>/dev/null; then
    apt-get update -qq
    apt-get install -y ufw
fi
echo " OK"

# =============================================================================
# STEP 2 — Abilita IPv6
# =============================================================================
echo "[2/8] Configurazione IPv6..."
sed -i 's/^IPV6=no/IPV6=yes/' /etc/default/ufw 2>/dev/null || true
grep -q "^IPV6=yes" /etc/default/ufw || echo "IPV6=yes" >> /etc/default/ufw
echo " OK — IPV6=yes impostato"

# =============================================================================
# STEP 3 — Reset completo
# =============================================================================
echo "[3/8] Reset regole ufw esistenti..."
ufw --force reset > /dev/null 2>&1
echo " OK — tabula rasa"

# =============================================================================
# STEP 4 — Policy di default
# =============================================================================
echo "[4/8] Policy di default..."
ufw default deny incoming
ufw default allow outgoing
ufw default deny routed
echo " OK — deny incoming, allow outgoing, deny routed"

# =============================================================================
# STEP 5 — Regole per servizio (con interfacce ed inoltro)
# =============================================================================
echo "[5/8] Applicazione regole..."

# Loopback (fondamentale per Pi-hole ↔ dnsproxy)
ufw allow in on lo comment "Consenti traffico interno (DNS loopback)"

# DNS QUIC outgoing (DoQ verso Quad9)
ufw allow out 853/udp comment "Allow Quad9 DoQ Outgoing"

# Tailscale WireGuard handshake
ufw allow in on "$TS" to any port 41641 proto udp comment "Tailscale WireGuard handshake"

# SSH
for subnet in 192.168.0.0/16 10.0.0.0/8 172.16.0.0/12; do
    ufw allow in on "$ETH" from "$subnet" to any port 22 proto tcp comment "SSH da LAN"
done
ufw allow in on "$TS" to any port 22 proto tcp comment "SSH da Tailscale"

# Pi-hole DNS
for subnet in 192.168.0.0/16 10.0.0.0/8 172.16.0.0/12; do
    ufw allow in on "$ETH" from "$subnet" to any port 53 proto udp comment "Pi-hole DNS UDP da LAN"
    ufw allow in on "$ETH" from "$subnet" to any port 53 proto tcp comment "Pi-hole DNS TCP da LAN"
    ufw reject in on "$ETH" from "$subnet" to any port 853 proto tcp comment "Fast-reject Android DoT TCP da LAN"
    ufw reject in on "$ETH" from "$subnet" to any port 853 proto udp comment "Fast-reject DoQ UDP da LAN"
done
ufw allow in on "$TS" to any port 53 proto udp comment "Pi-hole DNS UDP da Tailscale"
ufw allow in on "$TS" to any port 53 proto tcp comment "Pi-hole DNS TCP da Tailscale"
ufw reject in on "$TS" to any port 853 proto tcp comment "Fast-reject Android DoT TCP da Tailscale"
ufw reject in on "$TS" to any port 853 proto udp comment "Fast-reject DoQ UDP da Tailscale"

# Pi-hole Web UI
for subnet in 192.168.0.0/16 10.0.0.0/8 172.16.0.0/12; do
    ufw allow in on "$ETH" from "$subnet" to any port 80 proto tcp comment "Pi-hole Web UI HTTP da LAN"
    ufw allow in on "$ETH" from "$subnet" to any port 8080 proto tcp comment "Pi-hole Web UI HTTP da LAN"
    ufw allow in on "$ETH" from "$subnet" to any port 443 proto tcp comment "Pi-hole Web UI HTTPS da LAN"
done
ufw allow in on "$TS" to any port 80 proto tcp comment "Pi-hole Web UI HTTP da Tailscale"
ufw allow in on "$TS" to any port 443 proto tcp comment "Pi-hole Web UI HTTPS da Tailscale"

# Samba
for subnet in 192.168.0.0/16 10.0.0.0/8 172.16.0.0/12; do
    ufw allow in on "$ETH" from "$subnet" to any port 445 proto tcp comment "Samba SMB3 da LAN"
done
ufw allow in on "$TS" to any port 445 proto tcp comment "Samba SMB3 da Tailscale"

# Plex
for subnet in 192.168.0.0/16 10.0.0.0/8 172.16.0.0/12; do
    ufw allow in on "$ETH" from "$subnet" to any port 32400 proto tcp comment "Plex da LAN"
done
ufw allow in on "$TS" to any port 32400 proto tcp comment "Plex da Tailscale"

# Jellyfin
for subnet in 192.168.0.0/16 10.0.0.0/8 172.16.0.0/12; do
    ufw allow in on "$ETH" from "$subnet" to any port 8096 proto tcp comment "Jellyfin da LAN"
done
ufw allow in on "$TS" to any port 8096 proto tcp comment "Jellyfin da Tailscale"

# Transmission Web UI
for subnet in 192.168.0.0/16 10.0.0.0/8 172.16.0.0/12; do
    ufw allow in on "$ETH" from "$subnet" to any port 9091 proto tcp comment "Transmission Web UI da LAN"
done
ufw allow in on "$TS" to any port 9091 proto tcp comment "Transmission Web UI da Tailscale"

# Transmission BitTorrent (da qualsiasi IP, ma solo sulla LAN fisica)
ufw allow in on "$ETH" to any port 51413 proto tcp comment "Transmission BitTorrent TCP"
ufw allow in on "$ETH" to any port 51413 proto udp comment "Transmission BitTorrent UDP"

# Forwarding LAN <-> Tailscale (Routing)
ufw route allow in on "$ETH" out on "$TS" comment "Tailscale forwarding enp1s0 -> tailscale0"
ufw route allow in on "$TS" out on "$ETH" comment "Tailscale forwarding tailscale0 -> enp1s0"

echo " [OK] Tutte le regole applicate con interfaccia $ETH e $TS"

# =============================================================================
# STEP 6 — Attivazione
# =============================================================================
echo "[6/8] Attivazione ufw..."
ufw --force enable
echo " OK — ufw attivo"

# =============================================================================
# STEP 7 — Pulizia IPv6 e blocco IPv6 pubblico su enp1s0
# =============================================================================
echo "[7/8] Pulizia regole IPv6 indesiderate su $ETH e blocco IPv6 globale..."
while true; do
    num=$(ufw status numbered 2>/dev/null | grep -P '\(v6\).*on '"$ETH"'.*ALLOW IN' | head -1 | grep -oP '^\[\s*\K[0-9]+' || true)
    [[ -z "$num" ]] && break
    ufw --force delete "$num" > /dev/null 2>&1
done

ufw deny in on "$ETH" from 2000::/3 to any comment "Blocco IPv6 globale in ingresso su $ETH"
echo " [OK] Blocco IPv6 pubblico aggiunto"

# =============================================================================
# STEP 8 — Riepilogo finale
# =============================================================================
echo "[8/8] Verifica finale..."
echo ""
echo "=========================================="
echo " REGOLE ATTIVE"
echo "=========================================="
ufw status verbose
echo ""
echo "Interfaccia Ethernet rilevata: $ETH"
echo "Interfaccia Tailscale: $TS"
echo "Per controllare lo stato:   sudo ufw status numbered"
echo "Per ricaricare:             sudo ufw reload"
echo ""

echo "Script terminato correttamente!"
