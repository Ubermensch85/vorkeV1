# Hardware & Boot Configuration — Vorke V1 Plus

## 1. Caratteristiche Hardware
- **Modello:** Vorke V1 Plus Mini PC
- **Processore:** Intel Celeron J3455 @ 1.50GHz (burst 2.30GHz, 4 Cores, Architettura Goldmont / Apollo Lake)
- **Grafica integrata:** Intel HD Graphics 500 (Gen9, modulo `i915`)
- **Memoria RAM:** 4 GB DDR3L
- **Storage:** Disco primario SSD (ext4 con parametri `noatime,discard`)
- **Firmware BIOS:** American Megatrends UEFI 5.12

---

## 2. Workaround Batteria CMOS Esausta (`cmos-safe.cfg`)

Nei dispositivi Vorke V1 Plus con batteria a bottone CMOS scarica o disconnessa, la perdita della configurazione BIOS all'interruzione di alimentazione può causare instabilità con il timer di sistema HPET predefinito e blocchi in fase di boot.

Per garantire un riavvio headless sempre affidabile:

```ini
# Timeout visibile per selezione manuale se problemi
GRUB_TIMEOUT=5
GRUB_RECORDFAIL_TIMEOUT=5
GRUB_TIMEOUT_STYLE=menu

# Disabilita ricerca altri OS (velocizza boot)
GRUB_DISABLE_OS_PROBER=true

# Console testuale pura (affidabile, nessun crash framebuffer)
GRUB_TERMINAL=console
GRUB_GFXPAYLOAD_LINUX=text

# Kernel clocksource: forza TSC invece di HPET
GRUB_CMDLINE_LINUX_DEFAULT="quiet clocksource=tsc"
```

### Installazione
Copiare la configurazione in `/etc/default/grub.d/cmos-safe.cfg` ed eseguire:
```bash
sudo update-grub
```

---

## 3. Controllo Ventola con Isteresi (`fan-control.sh`)

Il firmware predefinito del Vorke V1 Plus tende a mantenere la ventola accesa a regimi fastidiosi o a oscillare rapidamente. Lo script `fan-control.sh` implementa una soglia con isteresi termica:

- **Soglia accensione ventola:** $\ge 55^\circ\text{C}$
- **Soglia spegnimento ventola:** $\le 45^\circ\text{C}$
- **Intervallo di campionamento:** ogni 5 secondi
- **Log rate-limiting:** logga solo al cambio di stato o ogni 5 minuti

### Device Sysfs monitorati:
- Temperatura CPU: `/sys/class/thermal/thermal_zone0/temp`
- Sensore RPM: `/sys/class/hwmon/hwmon1/fan1_input`
- Controllo ventola: `/sys/class/thermal/cooling_device5/cur_state` (1 = On, 0 = Off)

---

## 4. Moduli Kernel (`/etc/modprobe.d/`)

### Ottimizzazione grafica Intel (`i915.conf`):
```ini
options i915 enable_guc=2 enable_dc=0
```
- `enable_guc=2`: Abilita caricamento e autenticazione GuC/HuC per accelerazione hardware video e minore overhead CPU.
- `enable_dc=0`: Disabilita i deep power state del display controller (previene freeze del bus PCI su carichi headless).

### Blacklist Wi-Fi (`blacklist-iwlwifi.conf`):
```ini
blacklist iwlwifi
```
Disattiva la scheda wireless integrata per evitare tentativi di roaming radio, interrupt superflui e risparmiare risorse di alimentazione, lasciando attiva solo l'interfaccia cablata Gigabit `enp1s0`.
