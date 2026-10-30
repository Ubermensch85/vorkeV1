# Vorke V1 Plus — Home Server Configuration & Infrastructure Backup

Repository di backup e documentazione completa della configurazione del server domestico **Vorke V1 Plus** (Debian GNU/Linux 13 Trixie / Kernel 6.12).

---

## 📑 Indice

1. [Panoramica dell'Infrastruttura](#panoramica-dellinfrastruttura)
2. [Struttura del Repository](#struttura-del-repository)
3. [Componenti Principali](#componenti-principali)
   - [Hardware & Workaround Boot CMOS](#1-hardware--workaround-boot-cmos)
   - [Catena DNS (Pi-hole + dnsproxy)](#2-catena-dns-pi-hole--dnsproxy)
   - [Ottimizzazioni Kernel, Rete e Tailscale](#3-ottimizzazioni-kernel-rete-e-tailscale)
   - [Automazioni & Media Server](#4-automazioni--media-server)
   - [Bot Telegram & Monitoraggio](#5-bot-telegram--monitoraggio)
4. [Documentazione Dettagliata](#documentazione-dettagliata)
5. [Guida al Ripristino Rapido](#guida-al-ripristino-rapido)
6. [Sicurezza e Gestione Segreti](#sicurezza-e-gestione-segreti)

---

## Panoramica dell'Infrastruttura

- **Device:** Vorke V1 Plus (Intel Celeron J3455 4 Cores, 4GB RAM, SSD)
- **Ruolo:** DNS Sinkhole con DoQ/DoH3, Nodo Tailscale, Gateway protetto, automazione download e monitoraggio proattivo tramite Telegram.
- **Rete:** LAN Ethernet Gigabit + Tailscale WireGuard Overlay Network.

---

## Struttura del Repository

```
vorkeV1/
├── README.md                           # Documentazione principale
├── .env.example                        # Template per variabili e token di autenticazione
├── .gitignore                          # Esclusione log, file temporanei e segreti
├── docs/                               # Guide tecniche di dettaglio
│   ├── ARCHITECTURE.md                 # Diagramma flussi, porte e matrici servizi
│   ├── HARDWARE_AND_BOOT.md            # Workaround batteria CMOS e controllo ventola
│   ├── DNS_AND_NETWORK.md              # Configurazione Pi-hole v6, dnsproxy e sysctl
│   ├── AUTOMATIONS_AND_SERVICES.md     # Cleaner symlink, smistamento torrent, Plex
│   └── DISASTER_RECOVERY.md            # Procedura step-by-step per ripristino da zero
├── hardware-boot/                      # File di configurazione hardware e firmware
│   ├── cmos-safe.cfg                   # Parametri GRUB sicuri (clocksource=tsc)
│   ├── fan-control.sh                  # Demone di regolazione ventola con isteresi
│   ├── fan-control.service             # Servizio systemd per la ventola
│   ├── fstab.backup                    # Snapshot fstab (UUID e opzioni mount SSD)
│   ├── interfaces                      # Configurazione rete /etc/network/interfaces
│   ├── i915.conf                       # Opzioni modulo Intel i915 (GuC/HuC e DC)
│   └── blacklist-iwlwifi.conf          # Disattivazione scheda radio Wi-Fi non utilizzata
├── system-tuning/                      # Tuning delle prestazioni di sistema
│   ├── 99-network-performance.conf     # Sysctl BBR, buffer socket e sicurezza TCP/UDP
│   ├── 99-ssd.conf                     # Swappiness ridotta per longevità SSD
│   ├── ethtool-gro.service             # Ottimizzazione UDP GRO per throughput Tailscale
│   └── ufw-setup.sh                    # Configurazione firewall UFW restrittivo
├── dns-stack/                          # Resilienza e risoluzione DNS
│   ├── dnsproxy.service                # Unit systemd per AdGuard dnsproxy (DoQ/DoH3)
│   ├── dns-watchdog.sh                 # Monitoraggio continuo e ripristino automatico DNS
│   ├── dns-watchdog.service            # Unit servizio watchdog
│   ├── dns-watchdog.timer              # Timer watchdog (esecuzione ogni 2 minuti)
│   ├── guardian-update.sh              # Auto-update automatico binario dnsproxy da GitHub
│   ├── guardian-update.service         # Unit aggiornamento dnsproxy
│   ├── guardian-update.timer           # Timer periodico per aggiornamenti dnsproxy
│   ├── guardian-notify.sh              # Dispatcher notifiche Telegram con fallback
│   ├── install-guardian.sh             # Script di installazione dell'intero stack guardian
│   ├── set-telegram.sh                 # Configurazione interattiva credenziali Telegram
│   ├── update-dnsproxy.sh              # Script manuale aggiornamento dnsproxy
│   └── verify.sh                       # Suite diagnostica per validare la risoluzione DoQ/DNSSEC
├── automation-maintenance/             # Script operativi e di manutenzione
│   ├── update-system.sh                # Aggiornamento automatizzato Debian + Pi-hole
│   ├── setup-updates.sh                # Installazione cron/script di manutenzione
│   ├── symlink-cleaner.py              # Demone rimozione symlink orfani per film/serie
│   ├── symlink-cleaner.service         # Servizio systemd symlink-cleaner
│   ├── fix-dpkg-maintainer.py          # Correzione metadati pacchetti deb per APT
│   └── mount.sh                        # Auto-mount periferiche rimovibili USB
├── services-bot/                       # Monitoraggio remoto e gestione multimediale
│   ├── my_bot.py                       # Bot Telegram interattivo (status, pihole, tailscale)
│   ├── telegram-bot.service            # Unit systemd per my_bot.py
│   ├── telegram-send                   # Utility CLI per invio notifiche via curl
│   ├── daily-report.sh                 # Generatore report formattato con emoji e metriche
│   ├── torrent-done.sh                 # Hook notifica download completato
│   ├── torrent-sort.py                 # Smistatore intelligente film/serie e refresh Plex
│   ├── addtrackers.sh                  # Aggiunta tracker pubblici ai torrent Transmission
│   └── mariachiara.service             # Servizio systemd per bot aggiuntivo
└── user-config/
    └── zshrc                           # Configurazione shell ZSH e alias di sistema
```

---

## Componenti Principali

### 1. Hardware & Workaround Boot CMOS
Il dispositivo presenta la batteria tampone CMOS non funzionante. Per evitare blocchi al boot dovuti alla perdita dei registri hardware, `cmos-safe.cfg` impone al kernel `clocksource=tsc` e visualizza sempre il menu di boot GRUB in console testuale. Inoltre, `fan-control.sh` gestisce l'accensione della ventola solo quando la CPU supera i 55°C, spegnendola al di sotto dei 45°C.

### 2. Catena DNS (Pi-hole + dnsproxy)
- **Porta 53:** Pi-hole riceve il traffico DNS locale, applica le liste Gravity e inoltra a `127.0.0.1:5353`.
- **Porta 5353:** AdGuard `dnsproxy` inoltra le richieste in parallelo usando DNS-over-QUIC e DNS-over-HTTP/3 a Cloudflare e Quad9 con DNSSEC forzato.
- **DNS Guardian:** Due timer systemd verificano la risoluzione ogni 2 minuti e scaricano autonomamente i nuovi binari di `dnsproxy` al rilascio di release upstream.

### 3. Ottimizzazioni Kernel, Rete e Tailscale
- **BBR & Fair Queueing:** Attivato l'algoritmo di controllo della congestione BBR di Google.
- **Buffer di Rete:** Buffer rmem/wmem aumentati a 32MB per gestire flussi UDP veloci (WireGuard/Tailscale e QUIC).
- **Tailscale GRO:** Abilitato `rx-udp-gro-forwarding` su scheda Gigabit `enp1s0` per trasferimenti VPN a bassa latenza e ridotto carico CPU.

### 4. Automazioni & Media Server
- **Torrent sorting:** Al termine del download, `torrent-sort.py` rileva automaticamente se si tratta di una Serie TV o di un Film, crea i symlink corretti e richiede il refresh via API a Plex.
- **Symlink cleaner:** Controlla e rimuove link rotti lasciati da file rimossi.

### 5. Bot Telegram & Monitoraggio
- Notifiche in tempo reale in caso di riavvii, disconnessioni DNS o completamento download.
- Bot diagnostico `/status`, `/pihole`, `/tailscale`, `/torrent` con controllo accessi su ID Telegram autorizzato.

---

## Documentazione Dettagliata

Per approfondire ciascun sottosistema, consultare i documenti nella cartella `docs/`:
- [Architettura del Sistema e Flussi di Rete](docs/ARCHITECTURE.md)
- [Hardware, BIOS e Workaround CMOS](docs/HARDWARE_AND_BOOT.md)
- [Stack DNS, dnsproxy e Sysctl](docs/DNS_AND_NETWORK.md)
- [Automazioni, Media e Servizi di Background](docs/AUTOMATIONS_AND_SERVICES.md)
- [Procedura Completa di Disaster Recovery](docs/DISASTER_RECOVERY.md)

---

## Sicurezza e Gestione Segreti

Tutti i file tracciati in questo repository sono stati ripuliti da informazioni sensibili (token bot Telegram, password Transmission, token Plex).
Per rendere operativo l'ambiente dopo il ripristino:
1. Copiare `.env.example` in `/etc/vorke/vorke.env` e `/etc/dns-guardian/telegram.conf`.
2. Impostare i permessi restrittivi: `sudo chmod 600 /etc/dns-guardian/telegram.conf`.
3. Inserire i token e gli ID chat corretti.
