#!/usr/bin/env python3
import time
import requests
import subprocess
import os
import json

# --- CONFIGURAZIONE ---
# Lettura credenziali sicure da variabili d'ambiente o file di configurazione
TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "")
MY_CHAT_ID = int(os.environ.get("TELEGRAM_CHAT_ID", "0"))

if not TOKEN or not MY_CHAT_ID:
    for conf_path in [
        "/etc/dns-guardian/telegram.conf",
        os.path.expanduser("~/.config/dns-guardian/telegram.conf"),
        "/etc/vorke/telegram.conf"
    ]:
        if os.path.isfile(conf_path):
            try:
                with open(conf_path) as f:
                    for line in f:
                        line = line.strip()
                        if line.startswith("TELEGRAM_BOT_TOKEN="):
                            TOKEN = line.split("=", 1)[1].strip().strip('"').strip("'")
                        elif line.startswith("TELEGRAM_CHAT_ID="):
                            try:
                                MY_CHAT_ID = int(line.split("=", 1)[1].strip().strip('"').strip("'"))
                            except ValueError:
                                pass
                if TOKEN and MY_CHAT_ID:
                    break
            except Exception:
                pass

if not TOKEN:
    TOKEN = "YOUR_TELEGRAM_BOT_TOKEN"

URL = f"https://api.telegram.org/bot{TOKEN}/"

# URL SPECIFICO PER PI-HOLE v6
PIHOLE_API_URL = os.environ.get("PIHOLE_API_URL", "http://127.0.0.1:8080/api/stats/summary")
TR_AUTH = os.environ.get("TRANSMISSION_AUTH", "transmission:transmission")

def send_msg(text):
    if not text: return
    if len(text) > 4000: text = text[:4000] + "\n... [troncato]"
    try:
        requests.post(URL + "sendMessage", data={"chat_id": MY_CHAT_ID, "text": text, "parse_mode": "HTML"}, timeout=10)
    except Exception as e:
        print(f"Errore invio: {e}")

def run_cmd(cmd):
    try:
        return subprocess.check_output(cmd, shell=True, stderr=subprocess.STDOUT).decode('utf-8').strip()
    except subprocess.CalledProcessError:
        return None

def get_pihole_data():
    """Recupera JSON dalla nuova API v6 sulla porta 8080"""
    try:
        response = requests.get(PIHOLE_API_URL, timeout=3)
        if response.status_code == 200:
            return response.json()
        return None
    except Exception as e:
        print(f"Errore connessione Pi-hole: {e}")
        return None

def handle_command(command):
    cmd = command.lower().strip()
    
    # --- STATUS ---
    if cmd in ["/start", "/status"]:
        return run_cmd("/usr/local/bin/daily-report.sh")

    # --- PI-HOLE v6 (Fix Parsing) ---
    elif cmd == "/pihole":
        data = get_pihole_data()
        
        if data:
            try:
                queries = data.get('queries', {})
                gravity = data.get('gravity', {})
                
                blocked = int(queries.get('blocked', 0))
                total = int(queries.get('total', 0))
                percent = float(queries.get('percent_blocked', 0.0))
                domains = int(gravity.get('domains_being_blocked', 0))
                
                msg = "🛡️ <b>PI-HOLE v6 STATS</b>\n\n"
                msg += f"🚫 <b>Bloccati:</b> {blocked:,}\n"
                msg += f"🌍 <b>Query Totali:</b> {total:,}\n"
                msg += f"📉 <b>Percentuale:</b> {percent:.1f}%\n"
                msg += f"🦄 <b>Blacklist:</b> {domains:,}\n"
                
                status = run_cmd("systemctl is-active pihole-FTL")
                icon = "🟢" if status == "active" else "🔴"
                msg += f"\nStato FTL: {icon} {status}"
                return msg
            except Exception as e:
                return f"⚠️ Errore lettura dati: {str(e)}"
        else:
            return f"⚠️ <b>Errore API:</b> Impossibile contattare {PIHOLE_API_URL}"

    # --- TAILSCALE ---
    elif cmd == "/tailscale":
        raw = run_cmd("tailscale status")
        if raw:
            lines = raw.split('\n')
            msg = "🔗 <b>TAILSCALE NODES</b>\n\n<pre>"
            for line in lines:
                parts = line.split()
                if len(parts) >= 2:
                    ip, name = parts[0], parts[1]
                    if len(name) > 15: name = name[:14] + "…"
                    msg += f"{name.ljust(16)} {ip}\n"
            msg += "</pre>"
            return msg
        return "⚠️ Tailscale non attivo."

    # --- CLOUDFLARED ---
    elif cmd == "/cloudflared":
        raw = run_cmd("journalctl -u cloudflared -n 5 --no-pager --output=cat")
        if raw:
            clean_log = raw.replace("ERR", "🔴 ERR").replace("INF", "ℹ️ INF")
            return f"☁️ <b>CLOUDFLARED LOG</b>\n\n<pre>{clean_log}</pre>"
        return "Nessun log recente."

    # --- TORRENT ---
    elif cmd == "/torrent":
        raw = run_cmd(f"transmission-remote -n '{TR_AUTH}' -l")
        if not raw or "No torrents" in raw:
            return "⬇️ <b>Transmission</b>\n\nNessun download attivo."
        
        lines = raw.split('\n')
        msg = "⬇️ <b>TORRENT LIST</b>\n"
        count = 0
        for line in lines[1:-1]:
            parts = line.split()
            if len(parts) > 8:
                done_percent = parts[1]
                name = " ".join(parts[8:]) 
                if len(name) > 25: name = name[:20] + "..."
                status_icon = "✅" if "100%" in done_percent else "⏳"
                if "Stopped" in line: status_icon = "⏸️"
                msg += f"\n{status_icon} <b>{name}</b>\n   └─ {done_percent}"
                count += 1
        
        if count == 0: return "⬇️ <b>Transmission</b>\n\nNessun download attivo."
        return msg
    
    elif cmd == "/reboot":
        send_msg("⚠️ <b>Riavvio sistema...</b>")
        os.system("sleep 2 && sudo reboot")
        return None

    else:
        return "❓ Usa: /status, /pihole, /tailscale, /cloudflared, /torrent"

def main():
    offset = 0
    print("Bot Diagnostico Telegram avviato...")
    send_msg("✅ <b>Bot Diagnostico Avviato</b>")
    
    while True:
        try:
            r = requests.get(URL + "getUpdates", params={"offset": offset, "timeout": 60})
            data = r.json()
            if "result" in data:
                for item in data["result"]:
                    offset = item["update_id"] + 1
                    if "message" in item:
                        chat_id = item["message"]["chat"]["id"]
                        text = item["message"].get("text", "")
                        if (chat_id == MY_CHAT_ID or MY_CHAT_ID == 0) and text:
                            res = handle_command(text)
                            if res: send_msg(res)
        except Exception as e:
            print(f"Error: {e}")
            time.sleep(5)

if __name__ == "__main__":
    main()
