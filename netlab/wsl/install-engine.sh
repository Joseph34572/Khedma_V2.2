#!/bin/bash
# install-engine.sh - installs the NetLab engine inside the NetLab WSL distro:
#   Docker Engine (not Docker Desktop), containerlab, vrnetlab and small tools.
#
# Run by Setup (Windows) as:  wsl -d NetLab -u root -- /opt/netlab/wsl/install-engine.sh --yes
# Without --yes it asks before changing anything. Safe to run again.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_root

YES=0
[ "${1:-}" = "--yes" ] && YES=1

if [ "$YES" != 1 ]; then
    echo "This installs into the NetLab WSL distro (not into Windows):"
    echo "  - Docker Engine from download.docker.com"
    echo "  - containerlab from the netdevops apt repository"
    echo "  - vrnetlab (git clone into /opt/vrnetlab), used to build IOL images"
    echo "  - tools: tcpdump, jq, git, make, python3-yaml, telnet"
    read -r -p "Continue? [y/N] " a
    [[ $a =~ ^[Yy] ]] || die "cancelled"
fi

export DEBIAN_FRONTEND=noninteractive

info "Installing base tools"
apt-get update -q
apt-get install -y -q ca-certificates curl gnupg git make jq tcpdump iproute2 \
    telnet python3 python3-yaml rsync

# ------------------------------------------------------------ Docker Engine
if ! command -v dockerd >/dev/null 2>&1; then
    info "Installing Docker Engine (official Docker apt repository)"
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    codename=$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $codename stable" \
        > /etc/apt/sources.list.d/docker.list
    apt-get update -q
    apt-get install -y -q docker-ce docker-ce-cli containerd.io docker-buildx-plugin
else
    ok "Docker Engine already installed"
fi

# Small, rotated logs. The "userland proxy" stays on (default): it is what makes
# published ports (127.0.0.1:5001 ...) visible to Windows through WSL's
# localhost forwarding.
if [ ! -f /etc/docker/daemon.json ]; then
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json <<'EOF'
{
  "log-driver": "local",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
EOF
fi
systemctl enable docker >/dev/null 2>&1 || true
systemctl restart docker
docker_ready || die "Docker did not start (try: systemctl status docker)"
ok "Docker $(docker version --format '{{.Server.Version}}') is running"

# ------------------------------------------------------------- containerlab
if ! command -v containerlab >/dev/null 2>&1; then
    info "Installing containerlab (netdevops apt repository, as documented on containerlab.dev)"
    echo "deb [trusted=yes] https://netdevops.fury.site/apt/ /" > /etc/apt/sources.list.d/netdevops.list
    apt-get update -q
    apt-get install -y -q containerlab
else
    ok "containerlab already installed"
fi
ok "containerlab $(containerlab version 2>/dev/null | awk '/version:/ {print $2; exit}')"

# ----------------------------------------------------------------- vrnetlab
# hellt/vrnetlab now lives at srl-labs/vrnetlab (GitHub redirects the old name).
if [ ! -d /opt/vrnetlab/.git ]; then
    info "Cloning vrnetlab into /opt/vrnetlab"
    git clone --depth 1 https://github.com/srl-labs/vrnetlab.git /opt/vrnetlab
else
    info "Updating vrnetlab"
    git -C /opt/vrnetlab pull --ff-only -q || warn "could not update vrnetlab (offline?), keeping current copy"
fi

mkdir -p "$STATE/labs" "$STATE/incoming" "$STATE/reports"
touch "$IMAGES_ENV"

ok "Engine installed. Next: build the NetLab node images (build-images.sh)."
