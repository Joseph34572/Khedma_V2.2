#!/bin/bash
# build-images.sh - builds the NetLab node images from /opt/netlab/images:
#   netlab/base      Alpine + console + SSH helpers (shared layer, built once)
#   netlab/linux-pc  "Linux PC"
#   netlab/win-pc    "Windows PC" (Linux PC + winsh)
#   netlab/linux-fw  "Linux firewall" (nftables + fw CLI)
# Cisco images are not built here: see import-iol.sh.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_root
docker_ready || die "Docker is not running"

V=$(cat "$NETLAB/images/VERSION")
build() {          # build <name> [base-image]
    local name=$1 base=${2:-}
    info "Building netlab/$name:$V"
    if [ -n "$base" ]; then
        docker build -q --build-arg "BASE=$base" -t "netlab/$name:$V" "$NETLAB/images/$name" >/dev/null
    else
        docker build -q -t "netlab/$name:$V" "$NETLAB/images/$name" >/dev/null
    fi
}

build base
build linux-pc "netlab/base:$V"
build win-pc   "netlab/linux-pc:$V"
build linux-fw "netlab/base:$V"

echo
docker image ls --format 'table {{.Repository}}:{{.Tag}}\t{{.Size}}' | grep -E '^(REPOSITORY|netlab/)'
ok "NetLab node images are ready"
