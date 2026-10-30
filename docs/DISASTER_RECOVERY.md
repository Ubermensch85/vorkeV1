# Procedura di Disaster Recovery e Ripristino

Questa guida descrive i passaggi per reinstallare e ripristinare completamente il server Vorke V1 Plus partendo da un'installazione minima di Debian 13 (Trixie).

---

## 1. Prerequisiti
- Installazione Debian GNU/Linux 13 (netinst 64-bit) con utente principale e accesso `sudo`.
- Pacchetti base necessari:
  ```bash
  sudo apt update && sudo apt install -y git curl wget ethtool python3 python3-requests ufw zsh
  ```

---

## 2. Configurazione Hardware & Boot (Workaround CMOS)

1. Copiare la configurazione GRUB:
   ```bash
   sudo cp hardware-boot/cmos-safe.cfg /etc/default/grub.d/
   sudo update-grub
   ```
2. Installare i moduli e le opzioni kernel:
   ```bash
   sudo cp hardware-boot/i915.conf /etc/modprobe.d/
   sudo cp hardware-boot/blacklist-iwlwifi.conf /etc/modprobe.d/
   ```
3. Installare lo script di regolazione ventola:
   ```bash
   sudo cp hardware-boot/fan-control.sh /usr/local/bin/
   sudo chmod +x /usr/local/bin/fan-control.sh
   sudo cp hardware-boot/fan-control.service /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable --now fan-control.service
   ```

---

## 3. Ottimizzazioni Kernel e Firewall

1. Applicare le impostazioni sysctl:
   ```bash
   sudo cp system-tuning/99-network-performance.conf /etc/sysctl.d/
   sudo cp system-tuning/99-ssd.conf /etc/sysctl.d/
   sudo sysctl --system
   ```
2. Abilitare il servizio UDP GRO per Tailscale:
   ```bash
   sudo cp system-tuning/ethtool-gro.service /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable --now ethtool-gro.service
   ```
3. Configurare UFW:
   ```bash
   sudo bash system-tuning/ufw-setup.sh
   ```

---

## 4. Installazione dello Stack DNS (dnsproxy + Pi-hole)

1. Scaricare il binario `dnsproxy`:
   ```bash
   sudo bash dns-stack/update-dnsproxy.sh
   ```
2. Installare le unit systemd di dnsproxy e i watchdog:
   ```bash
   sudo cp dns-stack/dnsproxy.service /etc/systemd/system/
   sudo cp dns-stack/dns-watchdog.* /etc/systemd/system/
   sudo cp dns-stack/guardian-update.* /etc/systemd/system/
   sudo cp dns-stack/dns-watchdog.sh dns-stack/guardian-update.sh dns-stack/guardian-notify.sh /usr/local/bin/
   sudo chmod +x /usr/local/bin/dns-watchdog.sh /usr/local/bin/guardian-update.sh /usr/local/bin/guardian-notify.sh
   sudo systemctl daemon-reload
   sudo systemctl enable --now dnsproxy.service dns-watchdog.timer guardian-update.timer
   ```
3. Installare Pi-hole:
   ```bash
   curl -sSL https://install.pi-hole.net | bash
   ```
   Configurare `127.0.0.1#5353` come server DNS upstream personalizzato in Pi-hole.
4. Verificare il corretto funzionamento dell'intera catena DNS:
   ```bash
   bash dns-stack/verify.sh
   ```

---

## 5. Configurazione Credenziali & Servizi Bot

1. Creare la directory di configurazione protetta:
   ```bash
   sudo mkdir -p /etc/vorke /etc/dns-guardian
   sudo cp .env.example /etc/vorke/vorke.env
   sudo cp .env.example /etc/dns-guardian/telegram.conf
   sudo chmod 600 /etc/vorke/vorke.env /etc/dns-guardian/telegram.conf
   ```
   Modificare `/etc/dns-guardian/telegram.conf` con il token Telegram e la chat ID effettivi.
2. Installare gli script in `/usr/local/bin`:
   ```bash
   sudo cp services-bot/my_bot.py /usr/local/bin/
   sudo cp services-bot/telegram-send /usr/local/bin/
   sudo cp services-bot/daily-report.sh /usr/local/bin/
   sudo cp services-bot/torrent-sort.py /usr/local/bin/
   sudo cp automation-maintenance/symlink-cleaner.py /usr/local/bin/
   sudo cp automation-maintenance/update-system.sh /usr/local/bin/
   sudo cp automation-maintenance/fix-dpkg-maintainer.py /usr/local/bin/
   sudo chmod +x /usr/local/bin/*
   ```
3. Abilitare i servizi systemd dedicati:
   ```bash
   sudo cp services-bot/telegram-bot.service /etc/systemd/system/
   sudo cp automation-maintenance/symlink-cleaner.service /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable --now symlink-cleaner.service telegram-bot.service
   ```
