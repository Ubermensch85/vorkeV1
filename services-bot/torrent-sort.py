#!/usr/bin/env python3
import os
import re
import sys
import urllib.request

LOG_FILE = "/var/log/transmission-sort.log"
# Configurazione token Plex da env var con fallback a placeholder
PLEX_TOKEN = os.environ.get("PLEX_TOKEN", "YOUR_PLEX_TOKEN")

def log(message):
    print(message)
    try:
        with open(LOG_FILE, "a") as f:
            f.write(message + "\n")
    except Exception:
        pass

def is_tv_show(name):
    patterns = [
        r'(?i)(?:^|[^a-zA-Z0-9])s[0-9]+(?:e[0-9]+)?(?:[^a-zA-Z0-9]|$)',      # S01, S01E02, _S01E01_
        r'(?i)(?:^|[^a-zA-Z0-9])[0-9]+x[0-9]+(?:[^a-zA-Z0-9]|$)',           # 1x02, _1x02_
        r'(?i)(?:^|[^a-zA-Z0-9])season[._ -]?[0-9]+(?:[^a-zA-Z0-9]|$)',     # Season 1, Season.1
        r'(?i)(?:^|[^a-zA-Z0-9])stagione[._ -]?[0-9]+(?:[^a-zA-Z0-9]|$)',   # Stagione 1, Stagione.1
        r'(?i)(?:^|[^a-zA-Z0-9])ep(?:isodio)?[._ -]?[0-9]+(?:[^a-zA-Z0-9]|$)', # ep.01, ep01, episodio 1
    ]
    for pattern in patterns:
        if re.search(pattern, name):
            return True
    return False

def determine_category(source_path, torrent_name):
    if is_tv_show(torrent_name):
        return "SerieTV"
    if os.path.isdir(source_path):
        for root, dirs, files in os.walk(source_path):
            for d in dirs:
                if is_tv_show(d):
                    return "SerieTV"
            for f in files:
                if is_tv_show(f):
                    return "SerieTV"
    return "Film"

def trigger_plex_refresh(category):
    if not PLEX_TOKEN or PLEX_TOKEN == "YOUR_PLEX_TOKEN":
        log("Plex refresh saltato: PLEX_TOKEN non configurato.")
        return
    try:
        section_id = "7" if category == "SerieTV" else "5"
        url = f"http://127.0.0.1:32400/library/sections/{section_id}/refresh?X-Plex-Token={PLEX_TOKEN}"
        req = urllib.request.Request(url, method="GET")
        urllib.request.urlopen(req, timeout=5)
        log(f"Triggered Plex refresh for section {section_id} ({category})")
    except Exception as e:
        log(f"Could not trigger Plex refresh: {e}")

def main():
    torrent_dir = os.environ.get("TR_TORRENT_DIR")
    torrent_name = os.environ.get("TR_TORRENT_NAME")

    if not torrent_dir or not torrent_name:
        log("ERROR: Environment variables TR_TORRENT_DIR or TR_TORRENT_NAME not set.")
        sys.exit(1)

    source_path = os.path.join(torrent_dir, torrent_name)
    log(f"--- Processing: {torrent_name} ---")
    log(f"Source path: {source_path}")

    category = determine_category(source_path, torrent_name)
    dest_dir = os.path.join(os.path.expanduser("~"), "Scaricati", category)
    log(f"Classified as: {category}")

    allowed_exts = {".mp4", ".mkv", ".avi", ".m4v", ".mov", ".wmv", ".srt", ".sub", ".vtt"}

    def link_file(src, dest):
        dest_parent = os.path.dirname(dest)
        os.makedirs(dest_parent, exist_ok=True)
        try:
            os.chmod(dest_parent, 0o775)
        except Exception:
            pass
        if os.path.lexists(dest):
            if os.path.islink(dest) and not os.path.exists(dest):
                os.unlink(dest)
            else:
                log(f"Destination file already exists, skipping: {dest}")
                return
        try:
            os.symlink(src, dest)
            log(f"Symlinked: {src} -> {dest}")
        except Exception as e:
            log(f"Failed to symlink {src} to {dest}: {e}")

    if os.path.isfile(source_path):
        ext = os.path.splitext(source_path)[1].lower()
        if ext in allowed_exts:
            dest_path = os.path.join(dest_dir, torrent_name)
            link_file(source_path, dest_path)
    elif os.path.isdir(source_path):
        subdirs = [d for d in os.listdir(source_path) if os.path.isdir(os.path.join(source_path, d))]
        root_files = [f for f in os.listdir(source_path) if os.path.isfile(os.path.join(source_path, f))]
        has_redundant_root = (len(subdirs) == 1 and len(root_files) == 0)

        for root, dirs, files in os.walk(source_path):
            for file in files:
                ext = os.path.splitext(file)[1].lower()
                if ext in allowed_exts:
                    file_src = os.path.join(root, file)
                    if has_redundant_root:
                        rel_to_torrent = os.path.relpath(file_src, source_path)
                        file_dest = os.path.join(dest_dir, rel_to_torrent)
                    else:
                        rel_to_torrent_dir = os.path.relpath(file_src, torrent_dir)
                        file_dest = os.path.join(dest_dir, rel_to_torrent_dir)
                    link_file(file_src, file_dest)

    trigger_plex_refresh(category)
    print(f"CATEGORY={category}")

if __name__ == "__main__":
    main()
