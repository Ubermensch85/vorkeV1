# Automazioni e Servizi di Background

## 1. Pulizia Symlink Multimediali (`symlink-cleaner.py`)

Servizio demone continuo (`symlink-cleaner.service`) che monitora le directory dei contenuti multimediali:
- Directory controllate: `/home/ubermensch/Scaricati/Film` e `/home/ubermensch/Scaricati/SerieTV`
- Rileva ricorsivamente tutti i symlink la cui destinazione non esiste più (ad es. file eliminati o spostati).
- Rimuove i link orfani e provvede alla pulizia automatica delle directory vuote.
- Scrive i dettagli operativi nel log `/var/log/symlink-cleaner.log`.

---

## 2. Smistamento Automatico Download & Plex (`torrent-sort.py`)

Hook eseguito da Transmission al termine del download di un torrent:
1. Analizza il nome del torrent e della cartella mediante pattern regex avanzati per identificare serie TV (es. `S01E02`, `1x05`, `Stagione 1`, `ep02`).
2. Crea collegamenti simbolici strutturati nella rispettiva directory di destinazione (`Film` o `SerieTV`).
3. Notifica l'API del media server Plex per avviare la scansione immediata della sezione aggiornata (`/library/sections/{id}/refresh?X-Plex-Token=...`).
4. Invia una notifica Telegram all'utente tramite `torrent-done.sh`.

---

## 3. Bot Diagnostico Telegram (`my_bot.py`)

Bot interattivo (`telegram-bot.service`) in ascolto via long-polling per il controllo rapido dello stato del server:

- `/status` o `/start`: Genera una scheda visiva del server con stato aggiornamenti pacchetti, occupazione disco, conteggio ad bloccati, stato servizi critici (Pi-hole, dnsproxy, Tailscale) e torrent attivi.
- `/pihole`: Statistiche in tempo reale da Pi-hole v6 API (query totali, percentuali di blocco, domini in gravity).
- `/tailscale`: Elenco nodi connessi con IP e stato della VPN mesh.
- `/torrent`: Lista torrent attivi e percentuali di completamento.
- `/reboot`: Riavvio sicuro del server da remoto.

---

## 4. Aggiornamenti di Sistema (`update-system.sh`)

Script automatizzato per il mantenimento periodico della distribuzione Debian e dei componenti applicativi:
- Aggiornamento indice pacchetti (`apt-get update`).
- Avanzamento pacchetti (`apt-get dist-upgrade -y` in modalità non interattiva).
- Rimozione automatica delle dipendenze orfane e pulizia cache (`autoremove`, `autoclean`).
- Aggiornamento integrato di Pi-hole (`pihole updatePihole`).
