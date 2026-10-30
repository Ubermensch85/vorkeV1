# Architettura di Sistema — Vorke V1 Plus Home Server

## 1. Panoramica
Questo server opera come nodo domestico centrale per servizi essenziali di rete, sicurezza, caching DNS e automazione multimediale.

- **Hardware:** Vorke V1 Plus (Intel Celeron J3455 Apollo Lake, 4 Cores, 4GB RAM)
- **Sistema Operativo:** Debian GNU/Linux 13 (Trixie), Kernel 6.12+ (x86_64)
- **Rete Primaria:** Ethernet `enp1s0` (DHCP locale LAN)
- **Rete Overlay:** Tailscale VPN (`tailscale0`) con UDP GRO forwarding ottimizzato

---

## 2. Flusso del Traffico DNS e Risoluzione

La risoluzione DNS adotta un'architettura ibrida a doppio livello per unire blocco avanzato della pubblicità e privacy/crittografia ad alta velocità tramite protocolli moderni (DNS-over-QUIC e DNS-over-HTTP/3).

```
[ Client LAN / Tailscale ]
             │
             ▼  (Porta 53 UDP/TCP)
┌───────────────────────────────────────────────┐
│              Pi-hole (FTL v6)                 │
│  - Ad-blocking & Sinkholing                   │
│  - Blacklist Gravity locale                   │
│  - Risoluzione nomi host locali               │
└───────────────────────┬───────────────────────┘
                        │ Inoltro query pulite
                        │ (127.0.0.1:5353)
                        ▼
┌───────────────────────────────────────────────┐
│             AdGuard dnsproxy                  │
│  - Caching ottimistico (TTL 3600, 4MB cache)  │
│  - Validazione DNSSEC attiva                  │
│  - Richieste parallele upstream               │
└───────┬───────────────────────────────┬───────┘
        │ DoQ / DoH3                    │ DoQ / DoH3
        ▼                               ▼
┌─────────────────────────┐   ┌─────────────────────────┐
│   Cloudflare (1.0.0.2)  │   │     Quad9 (9.9.9.9)     │
│   h3://1.0.0.2          │   │  quic://9.9.9.9:853     │
└─────────────────────────┘   └─────────────────────────┘
```

---

## 3. Matrice dei Servizi Systemd

| Servizio | Tipo | Descrizione |
|---|---|---|
| `pihole-FTL.service` | Daemon | Resolver DNS sinkhole e interfaccia web |
| `dnsproxy.service` | Daemon | Proxy DNS crittografato (DoQ / DoH3) sulla porta 5353 |
| `dns-watchdog.timer` | Timer (ogni 2m) | Verifica la risoluzione locale e riavvia `dnsproxy` o `pihole` in caso di hang |
| `guardian-update.timer` | Timer | Controlla periodicamente nuove release di dnsproxy su GitHub |
| `fan-control.service` | Daemon | Regolazione ad isteresi della ventola del Vorke |
| `ethtool-gro.service` | Oneshot (boot) | Attiva UDP GRO e forwarding per Tailscale |
| `symlink-cleaner.service` | Daemon | Monitora le directory multimediali eliminando link simbolici orfani |
| `telegram-bot.service` | Daemon | Bot interattivo per comandi di diagnostica remota |
| `mariachiara.service` | Daemon | Servizio bot Telegram dedicato |
