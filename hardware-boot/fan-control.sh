#!/bin/bash
# Fan control Vorke V1 Plus
# Accende/spegne la ventola in base alla temperatura con hysteresis

TEMP_ON=55     # °C: accende ventola
TEMP_OFF=45    # °C: spegne ventola
COOLING_DEV="/sys/class/thermal/cooling_device5/cur_state"
SLEEP=5        # secondi tra un controllo e l'altro
LOG_INTERVAL=60 # Logga lo stato ogni 60 cicli (60 * 5s = 5 minuti)

count=$LOG_INTERVAL

while true; do
    # Legge temperatura CPU
    temp=$(cat /sys/class/thermal/thermal_zone0/temp)
    temp=$((temp/1000))

    # Legge stato ventola
    fan_rpm=$(cat /sys/class/hwmon/hwmon1/fan1_input)

    state_changed=0

    # Controllo accensione/spegnimento con hysteresis
    if [ "$temp" -ge "$TEMP_ON" ]; then
        # accende ventola se spenta
        current=$(cat "$COOLING_DEV")
        if [ "$current" -eq 0 ]; then
            echo 1 > "$COOLING_DEV"
            echo "$(date) - Fan ON (Temp: ${temp}°C, Fan RPM: $fan_rpm)"
            state_changed=1
        fi
    elif [ "$temp" -le "$TEMP_OFF" ]; then
        # spegne ventola se accesa
        current=$(cat "$COOLING_DEV")
        if [ "$current" -eq 1 ]; then
            echo 0 > "$COOLING_DEV"
            echo "$(date) - Fan OFF (Temp: ${temp}°C, Fan RPM: $fan_rpm)"
            state_changed=1
        fi
    fi

    # Logga periodicamente o ad ogni cambio di stato
    if [ $count -ge $LOG_INTERVAL ] || [ $state_changed -eq 1 ]; then
        if [ $state_changed -eq 0 ]; then
            echo "$(date) - Status: ${temp}°C, Fan RPM: $fan_rpm"
        fi
        count=0
    else
        count=$((count+1))
    fi

    sleep $SLEEP
done
