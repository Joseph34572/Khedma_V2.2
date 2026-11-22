#!/bin/bash
# sync.sh - copies the NetLab code from the Windows project folder into the
# NetLab WSL distro (/opt/netlab). The Windows scripts run it every time, so
# edits you make in the project folder are picked up automatically.
#
# Run from the project folder:  wsl -d NetLab -u root --cd <netlab folder> -- bash wsl/sync.sh
set -euo pipefail
src=$(pwd)
dst=/opt/netlab
[ -f "$src/wsl/lab.sh" ] || { echo "run this from the netlab project folder" >&2; exit 1; }
[ "$(id -u)" = 0 ] || { echo "run as root" >&2; exit 1; }

mkdir -p "$dst"
for d in wsl images labs config; do
    rm -rf "$dst/$d.new"
    cp -r "$src/$d" "$dst/$d.new"
    rm -rf "$dst/${d:?}"
    mv "$dst/$d.new" "$dst/$d"
done

# A Windows checkout can turn LF line endings into CRLF, which breaks Linux
# scripts. Remove any CR characters from the copied text files.
find "$dst" -type f ! -name '*.png' -exec sed -i 's/\r$//' {} +
chmod +x "$dst"/wsl/*.sh "$dst"/wsl/*.py
mkdir -p /var/lib/netlab/labs /var/lib/netlab/incoming /var/lib/netlab/reports
