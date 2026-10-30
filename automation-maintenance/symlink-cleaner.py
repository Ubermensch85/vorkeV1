#!/usr/bin/env python3
import os
import sys
import time
import logging

LOG_FILE = "/var/log/symlink-cleaner.log"
logging.basicConfig(
    filename=LOG_FILE,
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)

WATCH_DIRS = [
    "/home/ubermensch/Scaricati/Film",
    "/home/ubermensch/Scaricati/SerieTV"
]

def clean_broken_links():
    for target_dir in WATCH_DIRS:
        if not os.path.exists(target_dir):
            continue
        # Walk target_dir top-down=False to clean files first, then empty subdirectories
        for root, dirs, files in os.walk(target_dir, topdown=False):
            for file_name in files:
                file_path = os.path.join(root, file_name)
                # Check if it's a symlink whose target no longer exists
                if os.path.islink(file_path):
                    if not os.path.exists(file_path):
                        try:
                            os.unlink(file_path)
                            logging.info(f"Removed broken symlink: {file_path}")
                        except Exception as e:
                            logging.error(f"Error removing {file_path}: {e}")

            for dir_name in dirs:
                dir_path = os.path.join(root, dir_name)
                if os.path.islink(dir_path):
                    if not os.path.exists(dir_path):
                        try:
                            os.unlink(dir_path)
                            logging.info(f"Removed broken symlink dir: {dir_path}")
                        except Exception as e:
                            logging.error(f"Error removing dir link {dir_path}: {e}")
                elif os.path.isdir(dir_path):
                    # Remove empty directory if all symlinked files inside were cleaned
                    try:
                        if not os.listdir(dir_path):
                            os.rmdir(dir_path)
                            logging.info(f"Removed empty directory: {dir_path}")
                    except Exception as e:
                        pass

def main():
    logging.info("Starting Symlink Cleaner Daemon...")
    clean_broken_links()

    while True:
        try:
            time.sleep(3)
            clean_broken_links()
        except Exception as e:
            logging.error(f"Unexpected error in main loop: {e}")
            time.sleep(5)

if __name__ == "__main__":
    main()
