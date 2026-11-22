#!/bin/bash
# capture.sh - live packet capture on one link of a running lab.
#
#   capture.sh <lab-name> <node> <interface>   pcap stream on stdout (for Wireshark)
#   capture.sh links <lab>                     list the lab's links
#
# Interface names: Linux nodes use eth1, eth2, ...; IOL also accepts its CLI
# names (Ethernet0/2 or e0/2 = eth2, Ethernet1/0 = eth4: slot * 4 + port).
#
# Every link is a veth pair between two nodes. tcpdump runs inside the node's
# network namespace (containerlab names it after the container) on that end
# of the pair. The Windows script pipes this output straight into Wireshark:
#   wsl -d NetLab -u root -- /opt/netlab/wsl/capture.sh phase1 R1 Ethernet0/2 | Wireshark -k -i -
source "$(dirname "$0")/lib.sh"
require_root

if [ "${1:-}" = links ]; then
    lab=${2:?usage: capture.sh links <lab>}
    topo=$(ls "$STATE/labs/$lab"/*.clab.yml 2>/dev/null | head -n1)
    [ -n "$topo" ] || topo=$(ls "$NETLAB/labs/$lab"/*.clab.yml 2>/dev/null | head -n1)
    [ -n "$topo" ] || die "lab '$lab' not found"
    python3 "$NETLAB/wsl/netlab_topo.py" links "$topo"
    exit 0
fi

lab=${1:?usage: capture.sh <lab-name> <node> <interface>}
node=${2:?node}
ifname=${3:?interface}

# Ethernet0/2 or e0/2 -> eth2
if [[ $ifname =~ ^(Ethernet|ethernet|e|Et|et)([0-9]+)/([0-9]+)$ ]]; then
    ifname="eth$(( BASH_REMATCH[2] * 4 + BASH_REMATCH[3] ))"
fi

ns="clab-$lab-$node"
[ -e "/var/run/netns/$ns" ] || die "node $node of lab $lab is not running (no network namespace $ns)"
ip netns exec "$ns" test -e "/sys/class/net/$ifname" || die "$node has no interface $ifname"

echo "capturing on $node $ifname (close Wireshark to stop)" >&2
# -U: write each packet immediately, -s 0: whole packets, -w -: pcap to stdout
exec ip netns exec "$ns" tcpdump -U -nni "$ifname" -s 0 -w -
