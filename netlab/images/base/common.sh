#!/bin/bash
# NetLab shared helpers for the small Linux nodes.
# This file is "sourced" (loaded) by each image's init script and by winsh/fw,
# so it only defines variables and functions; it does nothing on its own.

# Paths can be overridden for the tests in tests/ (the defaults are the real ones).
NETLAB_RUN=${NETLAB_RUN:-/run/netlab}           # runtime state (lost when the node stops)
SYSNET=${NETLAB_SYSNET:-/sys/class/net}         # network interfaces
RESOLV=${NETLAB_RESOLV:-/etc/resolv.conf}       # DNS servers
mkdir -p "$NETLAB_RUN" 2>/dev/null

log() { echo "[netlab] $*"; }

# Lab interfaces are eth1, eth2, ... in numeric order.
# eth0 is containerlab's management network and is never part of the lab.
lab_ifaces() {
    ls "$SYSNET" 2>/dev/null | grep -E '^eth[1-9][0-9]*$' \
        | sed 's/^eth//' | sort -n | sed 's/^/eth/'
}

# containerlab starts the container first and plugs in the lab links
# afterwards. It tells us how many links to expect in CLAB_INTFS.
wait_for_links() {
    local want=${CLAB_INTFS:-0} have=0 i
    for i in $(seq 1 600); do                 # up to 120 s (600 x 0.2 s)
        have=$(lab_ifaces | wc -l)
        [ "$have" -ge "$want" ] && return 0
        sleep 0.2
    done
    log "warning: expected $want lab links but only $have appeared"
}

# The node must reach the lab only through its lab links. Docker gives eth0
# a default route and a DNS server pointing at the host: remove both.
# eth0 stays up, so the console and SSH keep working from the host.
isolate_mgmt() {
    ip route del default dev eth0 2>/dev/null
    ip -6 route del default dev eth0 2>/dev/null
    : > "$RESOLV" 2>/dev/null
}

# Console (telnet, port 5000) and SSH (port 22), then mark the node "ready".
start_services() {
    /usr/sbin/sshd
    telnetd -p 5000 -l /usr/local/lib/netlab/netlab-console -f /etc/netlab/banner
    # Ready time with sub-second precision (bash 5 $EPOCHREALTIME), for the boot report.
    echo "${EPOCHREALTIME:-$(date +%s)}" > "$NETLAB_RUN/ready"
}

# Keep PID 1's child alive until the node is stopped.
wait_forever() {
    exec sleep infinity
}

# set_static <iface> <ip/prefix> [gateway]
# Gives an interface a fixed address (stops DHCP on it first).
set_static() {
    local ifc=$1 cidr=$2 gw=${3:-}
    netlab-dhcp stop "$ifc" >/dev/null 2>&1
    ip -4 addr flush dev "$ifc"
    ip link set "$ifc" up
    ip addr add "$cidr" dev "$ifc" || return 1
    ip route del default dev "$ifc" 2>/dev/null
    if [ -n "$gw" ]; then
        ip route add default via "$gw" dev "$ifc" || return 1
    fi
    echo static > "$NETLAB_RUN/mode-$ifc"
    rm -f "$NETLAB_RUN/dhcp-$ifc.lease"
}

# set_dns "<server> [server2 ...]" [search-domain]
# Fixed DNS servers. An empty server list goes back to DNS learned by DHCP.
set_dns() {
    local servers=$1 domain=${2:-} s
    if [ -z "$servers" ]; then
        rm -f "$NETLAB_RUN/dns-static"
        return 0
    fi
    touch "$NETLAB_RUN/dns-static"
    {
        [ -n "$domain" ] && echo "search $domain"
        for s in $servers; do echo "nameserver $s"; done
    } > "$RESOLV"
}

# "dhcp" or "static" (what the interface was last configured with).
iface_mode() {
    cat "$NETLAB_RUN/mode-$1" 2>/dev/null || echo static
}
