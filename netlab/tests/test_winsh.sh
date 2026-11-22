#!/bin/bash
# Tests for winsh (the Windows-like shell) without Docker or a real network.
#
# Fake versions of ip, ping, traceroute, nslookup, netstat, hostname and
# netlab-dhcp print the same output formats as the real tools in the Alpine
# image, so the parsing and the Windows-style formatting can be checked.
#
#   bash tests/test_winsh.sh          (prints PASS/FAIL per check)
#   VERBOSE=1 bash tests/test_winsh.sh  (also prints each command's output)
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(dirname "$HERE")
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

# ---------------------------------------------------------------- fixtures
mkdir -p "$T/sys" "$T/run" "$T/bin" "$T/lib"
cp "$ROOT/images/base/common.sh" "$T/lib/"
mkif() { mkdir -p "$T/sys/$1"; echo "$2" > "$T/sys/$1/address"; echo "$3" > "$T/sys/$1/ifindex"; echo "$4" > "$T/sys/$1/operstate"; }
mkif eth0 aa:c1:ab:00:00:07 2 up
mkif eth1 aa:c1:ab:12:34:56 4 up
mkif eth2 aa:c1:ab:12:34:57 5 down
printf 'search lab\nnameserver 192.168.20.1\n' > "$T/resolv.conf"
echo dhcp > "$T/run/mode-eth1"
now=$(date +%s)
cat > "$T/run/dhcp-eth1.lease" <<EOF
IP=192.168.20.100
PREFIX=24
ROUTER="192.168.20.1"
DNS="192.168.20.1"
DOMAIN="lab"
SERVER=192.168.20.1
LEASE=86400
OBTAINED=$now
EOF
echo "4: eth1    inet 192.168.20.100/24 brd 192.168.20.255 scope global eth1\\       valid_lft forever preferred_lft forever" > "$T/addr-eth1"

# ------------------------------------------------------------------- mocks
cat > "$T/bin/ip" <<'EOF'
#!/bin/bash
a="$*"
case "$a" in
  "-4 -o addr show dev eth0") echo "2: eth0    inet 172.20.20.7/24 brd 172.20.20.255 scope global eth0\       valid_lft forever preferred_lft forever" ;;
  "-4 -o addr show dev eth1") cat "$T/addr-eth1" 2>/dev/null ;;
  "-4 -o addr show dev "*) ;;
  "-6 -o addr show dev eth1 scope link") echo "4: eth1    inet6 fe80::a8c1:abff:fe12:3456/64 scope link \       valid_lft forever preferred_lft forever" ;;
  "-6 -o addr show dev "*) ;;
  "-4 route show default dev eth1") grep -q . "$T/addr-eth1" 2>/dev/null && echo "default via 192.168.20.1 " ;;
  "-4 route show default dev "*) ;;
  "-4 route show")
     printf 'default via 192.168.20.1 dev eth1 \n172.20.20.0/24 dev eth0 proto kernel scope link src 172.20.20.7 \n192.168.20.0/24 dev eth1 proto kernel scope link src 192.168.20.100 \n10.0.0.0/8 via 192.168.20.254 dev eth1 \n' ;;
  "-4 neigh show dev eth1")
     printf '192.168.20.1 lladdr aa:bb:cc:00:01:11 REACHABLE\n192.168.20.5 lladdr aa:bb:cc:00:05:01 PERMANENT\n192.168.20.9  FAILED\n' ;;
  "-4 neigh show dev "*) ;;
  "-4 route get "*) echo "$4 via 192.168.20.1 dev eth1 src 192.168.20.100 uid 0" ;;
  "-4 addr flush dev "*) : > "$T/addr-eth1"; echo "ip $a" >> "$T/ip.log" ;;
  *) echo "ip $a" >> "$T/ip.log" ;;
esac
exit 0
EOF
cat > "$T/bin/ping" <<'EOF'
#!/bin/bash
size=56
while getopts "nc:W:s:t:" o; do case $o in s) size=$OPTARG ;; esac; done
target=${!#}
echo "PING $target ($target) $size($((size + 28))) bytes of data."
case $target in
  192.168.20.1) echo "$((size + 8)) bytes from $target: icmp_seq=1 ttl=255 time=0.412 ms"; exit 0 ;;
  3.3.3.3|203.0.113.10) echo "$((size + 8)) bytes from $target: icmp_seq=1 ttl=253 time=12.7 ms"; exit 0 ;;
  192.168.20.77) echo "From 192.168.20.100 icmp_seq=1 Destination Host Unreachable"; exit 1 ;;
  10.8.8.8) echo "From 10.0.13.2 icmp_seq=1 Destination Net Unreachable"; exit 1 ;;
  *) echo; echo "--- $target ping statistics ---"; echo "1 packets transmitted, 0 received, 100% packet loss, time 0ms"; exit 1 ;;
esac
EOF
cat > "$T/bin/traceroute" <<'EOF'
#!/bin/bash
if [ "${1:-}" = --help ]; then echo "Usage: traceroute [-46FIlnrv] [-f 1ST_TTL] [-m MAXTTL] [-q PROBES] [-w WAIT] HOST"; echo "	-I	Use ICMP ECHO instead of UDP datagrams"; exit 0; fi
echo "$*" > "$T/traceroute.args"
echo "traceroute to 3.3.3.3 (3.3.3.3), 30 hops max, 46 byte packets" >&2
printf ' 1  192.168.20.1  0.512 ms  0.305 ms  0.290 ms\n 2  10.0.13.2  1.234 ms  *  11.100 ms\n 3  *  *  *\n 4  3.3.3.3  2.001 ms  1.900 ms  1.800 ms\n'
EOF
cat > "$T/bin/nslookup" <<'EOF'
#!/bin/bash
name=$2; server=${3:-192.168.20.1}
printf 'Server:\t\t%s\nAddress:\t%s:53\n\n' "$server" "$server"
case $name in
  srv1.lab) printf 'Name:\tsrv1.lab\nAddress: 203.0.113.10\n\n' ;;
  r3.lab)   printf 'Name:\tr3.lab\nAddress: 3.3.3.3\n\n' ;;
  multi.lab) printf 'Name:\tmulti.lab\nAddress: 10.0.0.1\nName:\tmulti.lab\nAddress: 10.0.0.2\n\n' ;;
  *) echo "** server can't find $name: NXDOMAIN"; exit 1 ;;
esac
EOF
cat > "$T/bin/netstat" <<'EOF'
#!/bin/bash
if [ "$1" = -ant ]; then cat <<'X'
Active Internet connections (servers and established)
Proto Recv-Q Send-Q Local Address           Foreign Address         State
tcp        0      0 0.0.0.0:22              0.0.0.0:*               LISTEN
tcp        0      0 0.0.0.0:5000            0.0.0.0:*               LISTEN
tcp        0      0 172.20.20.7:5000        172.20.20.1:40000       ESTABLISHED
tcp        0      0 192.168.20.100:41234    203.0.113.10:80         ESTABLISHED
tcp        0      0 :::22                   :::*                    LISTEN
X
else cat <<'X'
Active Internet connections (servers and established)
Proto Recv-Q Send-Q Local Address           Foreign Address         State
udp        0      0 0.0.0.0:68              0.0.0.0:*
X
fi
EOF
cat > "$T/bin/hostname" <<'EOF'
#!/bin/bash
echo PC2
EOF
cat > "$T/bin/sleep" <<'EOF'
#!/bin/bash
exit 0
EOF
cat > "$T/bin/netlab-dhcp" <<'EOF'
#!/bin/bash
echo "netlab-dhcp $*" >> "$T/dhcp.log"
[ "$1" = renew ] && [ "${DHCP_FAIL:-0}" = 1 ] && exit 1
exit 0
EOF
chmod +x "$T/bin/"*

export T PATH="$T/bin:$PATH" NETLAB_LIB="$T/lib" NETLAB_RUN="$T/run" NETLAB_SYSNET="$T/sys" NETLAB_RESOLV="$T/resolv.conf"
WINSH="$ROOT/images/win-pc/winsh"

# ------------------------------------------------------------------ checks
pass=0; fail=0
run() { OUT=$(bash "$WINSH" -c "$1" 2>&1); RC=$?; [ "${VERBOSE:-0}" = 1 ] && { echo "----- C:\\>$1"; echo "$OUT"; }; }
has() {         # has "<description>" "<exact text expected somewhere in OUT>"
    if grep -qF -- "$2" <<<"$OUT"; then pass=$((pass + 1)); echo "PASS  $1"
    else fail=$((fail + 1)); echo "FAIL  $1"; echo "      expected: $2"; echo "$OUT" | sed 's/^/      | /'; fi
}
hasnt() {
    if grep -qF -- "$2" <<<"$OUT"; then fail=$((fail + 1)); echo "FAIL  $1 (must not contain: $2)"; echo "$OUT" | sed 's/^/      | /'
    else pass=$((pass + 1)); echo "PASS  $1"; fi
}

run "ipconfig"
has "ipconfig header"        "Windows IP Configuration"
has "adapter name"           "Ethernet adapter Ethernet:"
has "IPv4 address line"      "   IPv4 Address. . . . . . . . . . . : 192.168.20.100"
has "subnet mask line"       "   Subnet Mask . . . . . . . . . . . : 255.255.255.0"
has "gateway line"           "   Default Gateway . . . . . . . . . : 192.168.20.1"
has "DHCP DNS suffix"        "   Connection-specific DNS Suffix  . : lab"
has "link-local IPv6"        "   Link-local IPv6 Address . . . . . : fe80::a8c1:abff:fe12:3456%4"
has "second adapter down"    "   Media State . . . . . . . . . . . : Media disconnected"
hasnt "management hidden"    "172.20.20.7"

run "IPCONFIG /ALL"
has "/all host name"         "   Host Name . . . . . . . . . . . . : PC2"
has "/all MAC"               "   Physical Address. . . . . . . . . : AA-C1-AB-12-34-56"
has "/all DHCP enabled"      "   DHCP Enabled. . . . . . . . . . . : Yes"
has "/all preferred"         "192.168.20.100(Preferred)"
has "/all DHCP server"       "   DHCP Server . . . . . . . . . . . : 192.168.20.1"
has "/all lease obtained"    "   Lease Obtained. . . . . . . . . . : "
has "/all DNS servers"       "   DNS Servers . . . . . . . . . . . : 192.168.20.1"

run "ipconfig /renew"
has "renew prints adapter"   "Ethernet adapter Ethernet:"
grep -q "netlab-dhcp renew eth1" "$T/dhcp.log" && { pass=$((pass + 1)); echo "PASS  renew calls netlab-dhcp"; } || { fail=$((fail + 1)); echo "FAIL  renew calls netlab-dhcp"; }
DHCP_FAIL=1 run "ipconfig /renew"
has "renew failure message"  "unable to contact your DHCP server. Request has timed out."
run "ipconfig /bogus"
has "bad switch"             "Error: unrecognized or incomplete command line."

run "ping 192.168.20.1"
has "ping header"            "Pinging 192.168.20.1 with 32 bytes of data:"
has "ping reply <1ms"        "Reply from 192.168.20.1: bytes=32 time<1ms TTL=255"
has "ping stats"             "    Packets: Sent = 4, Received = 4, Lost = 0 (0% loss),"
has "ping rtt"               "    Minimum = 0ms, Maximum = 0ms, Average = 0ms"
run "ping -n 2 -l 100 r3"
has "ping resolves suffix"   "Pinging r3.lab [3.3.3.3] with 100 bytes of data:"
has "ping time"              "Reply from 3.3.3.3: bytes=100 time=12ms TTL=253"
has "ping count"             "Sent = 2, Received = 2, Lost = 0 (0% loss),"
run "ping -n 2 10.9.9.9"
has "ping timeout"           "Request timed out."
has "ping 100% loss"         "Sent = 2, Received = 0, Lost = 2 (100% loss),"
hasnt "no rtt when lost"     "Approximate round trip"
run "ping -n 1 192.168.20.77"
has "host unreachable"       "Reply from 192.168.20.100: Destination host unreachable."
has "unreachable counted"    "Sent = 1, Received = 1, Lost = 0 (0% loss),"
run "ping -n 1 10.8.8.8"
has "net unreachable"        "Reply from 10.0.13.2: Destination net unreachable."
run "ping nosuchhost"
has "unknown host"           "Ping request could not find host nosuchhost. Please check the name and try again."
run "ping -n 0 1.1.1.1"
has "bad -n value"           "Bad value for option -n"
run "ping"
has "ping usage"             "Usage: ping [-t] [-n count]"

run "tracert 3.3.3.3"
has "tracert header"         "Tracing route to 3.3.3.3 over a maximum of 30 hops"
has "tracert hop 1"          "  1    <1 ms    <1 ms    <1 ms  192.168.20.1"
has "tracert hop 2 mixed"    "  2     1 ms     *       11 ms  10.0.13.2"
has "tracert timeout hop"    "  3     *        *        *     Request timed out."
has "tracert last hop"       "  4     2 ms     1 ms     1 ms  3.3.3.3"
has "tracert complete"       "Trace complete."
grep -q -- "-I" "$T/traceroute.args" && { pass=$((pass + 1)); echo "PASS  tracert uses ICMP (-I)"; } || { fail=$((fail + 1)); echo "FAIL  tracert uses ICMP"; }
run "tracert srv1.lab"
has "tracert name header"    "Tracing route to srv1.lab [203.0.113.10]"

run "arp -a"
has "arp interface"          "Interface: 192.168.20.100 --- 0x4"
has "arp header"             "  Internet Address      Physical Address      Type"
has "arp dynamic"            "  192.168.20.1          aa-bb-cc-00-01-11     dynamic"
has "arp static"             "  192.168.20.5          aa-bb-cc-00-05-01     static"
has "arp broadcast"          "  192.168.20.255        ff-ff-ff-ff-ff-ff     static"
hasnt "arp failed hidden"    "192.168.20.9 "

run "nslookup srv1"
has "nslookup server"        "Address:  192.168.20.1"
has "nslookup name"          "Name:    srv1.lab"
has "nslookup address"       "Address:  203.0.113.10"
run "nslookup multi.lab"
has "nslookup multi"         "Addresses:  10.0.0.1"
has "nslookup multi 2"       "          10.0.0.2"
run "nslookup nothere.lab"
has "nslookup nxdomain"      "*** UnKnown can't find nothere.lab: Non-existent domain"

run "netstat"
has "netstat header"         "  Proto  Local Address          Foreign Address        State"
has "netstat established"    "  TCP    192.168.20.100:41234   203.0.113.10:80        ESTABLISHED"
hasnt "netstat no listen"    "LISTENING"
hasnt "netstat hides console" ":5000"
run "netstat -an"
has "netstat -a listening"   "  TCP    0.0.0.0:22             0.0.0.0:0              LISTENING"
has "netstat ipv6"           "  TCP    [::]:22                [::]:0                 LISTENING"
has "netstat udp"            "  UDP    0.0.0.0:68             *:*"

run "route print"
has "route header"           "Network Destination        Netmask          Gateway       Interface  Metric"
has "route default"          "          0.0.0.0          0.0.0.0     192.168.20.1   192.168.20.100     25"
has "route on-link"          "     192.168.20.0    255.255.255.0          On-link   192.168.20.100    281"
has "route static"           "         10.0.0.0        255.0.0.0   192.168.20.254   192.168.20.100     25"
has "route broadcast"        "   192.168.20.255  255.255.255.255          On-link   192.168.20.100    281"
hasnt "route hides mgmt"     "172.20.20"
run "route add 10.50.0.0 mask 255.255.0.0 192.168.20.1"
has "route add ok"           " OK!"
grep -q "ip route add 10.50.0.0/16 via 192.168.20.1" "$T/ip.log" && { pass=$((pass + 1)); echo "PASS  route add runs ip route add"; } || { fail=$((fail + 1)); echo "FAIL  route add runs ip route add"; }
run "route add 10.50.0.0 mask 255.0.255.0 192.168.20.1"
has "route add bad mask"     "The route addition failed: The parameter is incorrect."

run 'netsh interface ip set address "Ethernet" static 192.168.20.50 255.255.255.0 192.168.20.1'
grep -q "ip addr add 192.168.20.50/24 dev eth1" "$T/ip.log" && { pass=$((pass + 1)); echo "PASS  netsh static sets address"; } || { fail=$((fail + 1)); echo "FAIL  netsh static sets address"; cat "$T/ip.log"; }
grep -q "ip route add default via 192.168.20.1 dev eth1" "$T/ip.log" && { pass=$((pass + 1)); echo "PASS  netsh static sets gateway"; } || { fail=$((fail + 1)); echo "FAIL  netsh static sets gateway"; }
[ "$(cat "$T/run/mode-eth1")" = static ] && { pass=$((pass + 1)); echo "PASS  netsh static switches mode"; } || { fail=$((fail + 1)); echo "FAIL  netsh static switches mode"; }
run 'ipconfig /release'
has "release on static fails" "The operation failed as no adapter is in the state permissible for"
run 'netsh interface ip set address name="Ethernet 9" source=static address=1.2.3.4 mask=255.0.0.0'
has "netsh unknown adapter"  "The filename, directory name, or volume label syntax is incorrect."
run 'netsh interface ip set dns "Ethernet" static 192.168.20.2'
grep -q "nameserver 192.168.20.2" "$T/resolv.conf" && { pass=$((pass + 1)); echo "PASS  netsh dns static"; } || { fail=$((fail + 1)); echo "FAIL  netsh dns static"; }
run 'netsh interface ip show config'
has "netsh show config"      'Configuration for interface "Ethernet"'
has "netsh show static"      "    DHCP enabled:                         No"

run "dir"
has "unknown command"        "'dir' is not recognized as an internal or external command,"
run "HOSTNAME"
has "hostname"               "PC2"
run "echo Hello World"
has "echo"                   "Hello World"

echo
echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
