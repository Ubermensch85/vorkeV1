#!/bin/bash
# =============================================================================
# addtrackers.sh — Aggiunta tracker pubblici ai torrent attivi su Transmission
# =============================================================================

# Credenziali Transmission (configurabili tramite variabile o default)
auth="${TRANSMISSION_AUTH:-username:password}"
host="${TRANSMISSION_HOST:-localhost}"

add_trackers () {
    torrent_hash=$1
    for base_url in https://raw.githubusercontent.com/ngosang/trackerslist/master/trackers_all.txt ; do
        echo -e "\e[1mURL for ${base_url}\e[0m"
        for tracker in $(curl -s "${base_url}") ; do
            echo -ne "\e[93m*\e[0m ${tracker}..."
            if transmission-remote "$host" --auth="$auth" --torrent "${torrent_hash}" -td "${tracker}" | grep -q 'success'; then
                echo -e '\e[92m done.\e[0m'
            else
                echo -e '\e[91m failed.\e[0m'
            fi
        done
    done

    for base_url in https://newtrackon.com/api/stable ; do
        echo -e "\e[1mURL for ${base_url}\e[0m"
        for tracker in $(curl -s "${base_url}") ; do
            echo -ne "\e[93m*\e[0m ${tracker}..."
            if transmission-remote "$host" --auth="$auth" --torrent "${torrent_hash}" -td "${tracker}" | grep -q 'success'; then
                echo -e '\e[92m done.\e[0m'
            else
                echo -e '\e[91m failed.\e[0m'
            fi
        done
    done
}

if ! command -v transmission-remote &> /dev/null; then
    echo "Errore: transmission-remote non installato."
    exit 1
fi

ids="$(transmission-remote "$host" --auth="$auth" --list 2>/dev/null | grep -vE 'Seeding|Stopped|Finished' | grep '^ ' | awk '{ print $1 }')"

for id in $ids ; do
    hash="$(transmission-remote "$host" --auth="$auth" --torrent "$id" --info 2>/dev/null | grep '^  Hash: ' | awk '{ print $2 }')"
    torrent_name="$(transmission-remote "$host" --auth="$auth" --torrent "$id" --info 2>/dev/null | grep '^  Name: ' | cut -c 9-)"
    echo "Aggiunta tracker per: $torrent_name ($hash)"
    add_trackers "$hash"
done
