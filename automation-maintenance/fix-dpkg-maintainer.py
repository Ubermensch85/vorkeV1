#!/usr/bin/env python3
import os
import sys
import subprocess
import tempfile

DEFAULT_MAINTAINER = "latest-debs <latest-debs@users.noreply.github.com>"

def fix_deb_file(deb_path):
    if not os.path.isfile(deb_path) or not deb_path.endswith(".deb"):
        return
    try:
        maint = subprocess.check_output(
            ["dpkg-deb", "-f", deb_path, "Maintainer"],
             stderr=subprocess.DEVNULL,
            text=True
        ).strip()
        if maint:
            return
        with tempfile.TemporaryDirectory() as tmp:
            members = subprocess.check_output(["ar", "t", deb_path], text=True).splitlines()
            ctrl_member = next((m for m in members if m.startswith("control.tar")), None)
            if not ctrl_member:
                return
            subprocess.run(["ar", "x", deb_path, ctrl_member], cwd=tmp, check=True)
            ctrl_dir = os.path.join(tmp, "ctrl")
            os.makedirs(ctrl_dir, exist_ok=True)
            ctrl_archive = os.path.join(tmp, ctrl_member)
            subprocess.run(["tar", "-xf", ctrl_archive, "-C", ctrl_dir], check=True)
            ctrl_file = os.path.join(ctrl_dir, "control")
            if not os.path.isfile(ctrl_file):
                return
            with open(ctrl_file, "r", encoding="utf-8", errors="replace") as f:
                lines = f.read().splitlines()
            new_lines = []
            replaced = False
            for line in lines:
                if line.startswith("Maintainer:"):
                    new_lines.append(f"Maintainer: {DEFAULT_MAINTAINER}")
                    replaced = True
                else:
                    new_lines.append(line)
            if not replaced:
                new_lines.insert(1, f"Maintainer: {DEFAULT_MAINTAINER}")
            with open(ctrl_file, "w", encoding="utf-8") as f:
                f.write("\n".join(new_lines) + "\n")
            os.remove(ctrl_archive)
            subprocess.run(["tar", "-caf", ctrl_archive, "-C", ctrl_dir, "."], check=True)
            subprocess.run(["ar", "r", deb_path, ctrl_archive], check=True, stderr=subprocess.DEVNULL)
    except Exception:
        pass

def fix_status_file(status_path):
    if not os.path.isfile(status_path):
        return
    try:
        with open(status_path, "r", encoding="utf-8", errors="replace") as f:
            content = f.read()
        raw_stanzas = content.split("\n\n")
        modified = False
        new_stanzas = []
        for stanza in raw_stanzas:
            if not stanza.strip():
                new_stanzas.append(stanza)
                continue
            lines = stanza.splitlines()
            has_pkg = any(l.startswith("Package:") for l in lines)
            has_maint = any(l.startswith("Maintainer:") and l.split(":", 1)[1].strip() for l in lines)
            if has_pkg and not has_maint:
                modified = True
                out_lines = []
                inserted = False
                for l in lines:
                    if l.startswith("Maintainer:"):
                        out_lines.append(f"Maintainer: {DEFAULT_MAINTAINER}")
                        inserted = True
                    else:
                        out_lines.append(l)
                        if not inserted and l.startswith("Architecture:"):
                            out_lines.append(f"Maintainer: {DEFAULT_MAINTAINER}")
                            inserted = True
                if not inserted:
                    out_lines.insert(1, f"Maintainer: {DEFAULT_MAINTAINER}")
                new_stanzas.append("\n".join(out_lines))
            else:
                new_stanzas.append(stanza)
        if modified:
            tmp_path = status_path + ".tmp-fix"
            with open(tmp_path, "w", encoding="utf-8") as f:
                f.write("\n\n".join(new_stanzas))
            os.chmod(tmp_path, 0o644)
            os.replace(tmp_path, status_path)
    except Exception:
        pass

def main():
    if "--pre-install" in sys.argv:
        for line in sys.stdin:
            deb_path = line.strip()
            if deb_path:
                fix_deb_file(deb_path)
    fix_status_file("/var/lib/dpkg/status")
    fix_status_file("/var/lib/dpkg/status-old")

if __name__ == "__main__":
    main()
