#!/bin/bash
# Shared helpers for the NetLab scripts that run inside the NetLab WSL distro.
# (Sourced by the other scripts; it does nothing on its own.)

NETLAB=/opt/netlab               # code, image sources and lab templates (copied from Windows)
STATE=/var/lib/netlab            # running labs, built-image list, incoming images
IMAGES_ENV=$STATE/images.env     # which IOL images were built (written by import-iol.sh)

if [ -t 1 ]; then
    C_RED=$'\e[31m'; C_GRN=$'\e[32m'; C_YEL=$'\e[33m'; C_CYN=$'\e[36m'; C_OFF=$'\e[0m'
else
    C_RED=""; C_GRN=""; C_YEL=""; C_CYN=""; C_OFF=""
fi

info() { echo "${C_CYN}==>${C_OFF} $*"; }
ok()   { echo "${C_GRN}OK${C_OFF}  $*"; }
warn() { echo "${C_YEL}WARNING:${C_OFF} $*" >&2; }
die()  { echo "${C_RED}ERROR:${C_OFF} $*" >&2; exit 1; }

require_root() {
    [ "$(id -u)" = 0 ] || die "run this as root (the Windows scripts use: wsl -u root)"
}

# Reads one value from the settings file with jq.
#   setting '.deploy.maxWorkers' 0
setting() {
    local query=$1 default=$2 file v
    for file in "$NETLAB/config/settings.json" "$NETLAB/config/settings.default.json"; do
        [ -f "$file" ] || continue
        v=$(jq -r "$query // empty" "$file" 2>/dev/null)
        if [ -n "$v" ]; then echo "$v"; return; fi
    done
    echo "$default"
}

# Number of nodes containerlab may create in parallel (0 = CPU threads).
max_workers() {
    local w
    w=$(setting '.deploy.maxWorkers' 0)
    if [ "$w" -le 0 ] 2>/dev/null; then w=$(nproc); fi
    echo "$w"
}

load_images_env() {
    # shellcheck disable=SC1090
    [ -f "$IMAGES_ENV" ] && { set -a; . "$IMAGES_ENV"; set +a; }
    return 0
}

docker_ready() {
    docker info >/dev/null 2>&1 && return 0
    systemctl start docker >/dev/null 2>&1 || service docker start >/dev/null 2>&1
    local i
    for i in $(seq 1 30); do
        docker info >/dev/null 2>&1 && return 0
        sleep 1
    done
    return 1
}
