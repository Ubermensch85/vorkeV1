#!/bin/bash
# ~/mount.sh
# Script per montare automaticamente periferiche USB

# Configurazione
MOUNT_POINT="$HOME/Pennetta"
USER_ID=$(id -u)
GROUP_ID=$(id -g)

echo "=== Auto-mount USB Device ==="

# Metodo 1: Prova a cercare /dev/sdc1 se lo hai già visto
if [ -b "/dev/sdc1" ]; then
    DEVICE="/dev/sdc1"
    echo "Trovato: /dev/sdc1"
else
    # Metodo 2: Cerca l'ultimo dispositivo USB inserito
    DEVICE=$(lsblk -nrpo NAME,TYPE,TRAN | awk '$2=="part" && $3=="usb" {print $1}' | tail -n1)
    
    if [ -z "$DEVICE" ]; then
        # Metodo 3: Cerca dispositivi rimovibili
        DEVICE=$(lsblk -nrpo NAME,TYPE,RM | awk '$2=="part" && $3=="1" {print $1}' | tail -n1)
    fi
fi

if [ -z "$DEVICE" ]; then
    echo "Errore: Nessuna periferica USB rilevata"
    echo ""
    echo "Dispositivi disponibili:"
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE
    exit 1
fi

echo "Dispositivo rilevato: $DEVICE"

# Rileva il filesystem
FS_TYPE=$(lsblk -no FSTYPE "$DEVICE")

if [ -z "$FS_TYPE" ]; then
    echo "Errore: Impossibile rilevare il filesystem"
    sudo blkid "$DEVICE"
    exit 1
fi

echo "Filesystem: $FS_TYPE"

# Determina le opzioni di mount
case "$FS_TYPE" in
    exfat)
        MOUNT_OPTIONS="uid=$USER_ID,gid=$GROUP_ID,dmask=022,fmask=133"
        ;;
    vfat|fat32|msdos)
        MOUNT_OPTIONS="uid=$USER_ID,gid=$GROUP_ID,dmask=022,fmask=133,utf8"
        ;;
    ntfs|ntfs3)
        MOUNT_OPTIONS="uid=$USER_ID,gid=$GROUP_ID,dmask=022,fmask=133"
        ;;
    ext4|ext3|ext2)
        MOUNT_OPTIONS="defaults"
        ;;
    *)
        echo "Filesystem non supportato: $FS_TYPE"
        exit 1
        ;;
esac

# Crea mount point
mkdir -p "$MOUNT_POINT"

# Verifica se già montato
if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
    echo "ATTENZIONE: $MOUNT_POINT già in uso"
    read -p "Vuoi smontare? (s/n): " risposta
    if [ "$risposta" = "s" ] || [ "$risposta" = "S" ]; then
        sudo umount "$MOUNT_POINT"
        echo "Smontato"
    else
        exit 1
    fi
fi

# Monta il dispositivo
echo "Montaggio in corso..."
if sudo mount -o "$MOUNT_OPTIONS" "$DEVICE" "$MOUNT_POINT"; then
    echo "OK! Pennetta montata in: $MOUNT_POINT"
    echo ""
    df -h "$MOUNT_POINT" | tail -n1
    echo ""
    echo "Per smontare: sudo umount $MOUNT_POINT"
else
    echo "ERRORE durante il montaggio"
    exit 1
fi
