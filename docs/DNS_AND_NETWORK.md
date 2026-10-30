# Stack DNS e Ottimizzazione di Rete

## 1. Architettura della Catena DNS

La catena DNS combina la protezione di **Pi-hole v6** con le performance di **dnsproxy (AdGuard)**:

1. **Pi-hole (porta 53)**:
   - Riceve le richieste DNS da tutti i dispositivi della rete domestica.
   - Filtra telemetria, pubblicità, tracker e domini malevoli.
   - Ha come unico upstream `127.0.0.1#5353`.

2. **dnsproxy (porta 5353)**:
   - Risolve le query non bloccate inoltrandole in parallelo verso resolver DoQ / DoH3:
     - `h3://1.0.0.2/dns-query` (Cloudflare HTTP/3)
     - `https://1.0.0.2/dns-query` (Cloudflare HTTPS)
     - `quic://9.9.9.9:853` (Quad9 QUIC)
     - `quic://149.112.112.9:853` (Quad9 QUIC secondario)
   - Valida la catena crittografica DNSSEC.
   - Implementa cache ottimistica (TTL max 3600, dimensione 4MB) per servire risposte sub-millisecondo.

---

## 2. DNS Guardian (Watchdog & Updater)

Lo stack include una suite di resilienza automatica contenuta in `dns-stack/`:

- **`dns-watchdog.sh`** (eseguito dal timer `dns-watchdog.timer` ogni 2 minuti):
  - Testa la risoluzione DNS locale sia su Pi-hole (porta 53) sia su dnsproxy (porta 5353).
  - Se un servizio non risponde, tenta il riavvio selettivo via systemd.
  - Invia notifica immediata su Telegram in caso di degradazione o ripristino del servizio.

- **`guardian-update.sh`** (eseguito da `guardian-update.timer`):
  - Interroga le release GitHub di AdguardTeam/dnsproxy.
  - Se è disponibile un aggiornamento binario, effettua il download, verifica l'integrità e riavvia `dnsproxy.service` in modo trasparente.

- **`verify.sh`**:
  - Script diagnostico interattivo per validare la connettività upstream, la risoluzione DoQ, il blocco Pi-hole e il corretto fallimento dei domini DNSSEC non validi (`dnssec-failed.org`).

---

## 3. Ottimizzazione Rete Kernel (`99-network-performance.conf`)

Configurazione avanzata del kernel Linux per carichi FTTH ad alta velocità e tunnel Tailscale (WireGuard):

```ini
# Algoritmo di congestione BBR + Fair Queueing
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# Buffer socket dimensionati per 4GB RAM + flussi UDP QUIC/WireGuard
net.core.rmem_max = 33554432
net.core.wmem_max = 33554432
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
net.ipv4.tcp_rmem = 4096 131072 33554432
net.ipv4.tcp_wmem = 4096 131072 33554432
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384

# Coda pacchetti e backlog per burst di traffico
net.core.netdev_max_backlog = 16384
net.core.somaxconn = 4096
net.ipv4.tcp_max_syn_backlog = 4096

# TCP Fast Open (Client + Server) & Scaling
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1

# Protezioni di rete & compatibilità routing Tailscale
net.ipv4.conf.all.rp_filter = 2
net.ipv4.conf.default.rp_filter = 2
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_rfc1337 = 1
```

---

## 4. Tailscale UDP GRO Offloading (`ethtool-gro.service`)

Tailscale raccomanda l'attivazione dell'UDP Generic Receive Offloading (GRO) e dell'UDP forwarding sull'interfaccia fisica per ridurre l'utilizzo della CPU sui trasferimenti ad alto throughput:

```ini
[Service]
Type=oneshot
ExecStart=/sbin/ethtool -K enp1s0 gro on rx-gro-list off rx-udp-gro-forwarding on
RemainAfterExit=yes
```

---

## 5. Firewall UFW (`ufw-setup.sh`)

Lo script `ufw-setup.sh` configura il firewall applicando il principio del minimo privilegio:
- Accesso SSH limitato alla sottorete LAN locale e all'interfaccia sicura `tailscale0`.
- Traffico DNS (porta 53 UDP/TCP) autorizzato dalla LAN locale e dai nodi Tailscale.
- Interfaccia web Pi-hole (porta 80/443 e 8080) accessibile solo da indirizzi sicuri.
- Politica predefinita di blocco per tutto il traffico in ingresso non esplicitamente consentito.
