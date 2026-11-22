#!/bin/bash
# Tests for the firewall CLI (fw) without Docker: config parsing, validation,
# ordering, the generated nftables rules and the "show rules" counters.
# ip, nft, conntrack and hostname are replaced by small fakes.
#
#   bash tests/test_fw.sh            VERBOSE=1 bash tests/test_fw.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(dirname "$HERE")
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

mkdir -p "$T/sys/eth0" "$T/sys/eth1" "$T/sys/eth2" "$T/run" "$T/bin" "$T/lib"
for i in eth0 eth1 eth2; do echo up > "$T/sys/$i/operstate"; done
cp "$ROOT/images/base/common.sh" "$T/lib/"
cp "$ROOT/labs/phase1/configs/FW1.fw.conf" "$T/fw.conf"

cat > "$T/bin/ip" <<'EOF'
#!/bin/bash
a="$*"
echo "ip $a" >> "$T/ip.log"
case "$a" in
  "-4 -o addr show dev eth0") echo "2: eth0    inet 172.20.20.5/24 brd 172.20.20.255 scope global eth0" ;;
  "-4 route show proto static") cat "$T/routes" 2>/dev/null ;;
  "-4 route show") printf '10.0.34.0/30 dev eth1 proto kernel scope link src 10.0.34.2\ndefault via 10.0.34.1 dev eth1 proto static\n172.20.20.0/24 dev eth0 proto kernel scope link src 172.20.20.5\n' ;;
esac
exit 0
EOF
cat > "$T/bin/nft" <<'EOF'
#!/bin/bash
if [ "$1" = -f ]; then cp "$2" "$T/last.nft"; [ "${NFT_FAIL:-0}" = 1 ] && exit 1; exit 0; fi
if [ "$*" = "list chain inet netlab forward" ]; then cat <<'X'
table inet netlab {
	chain forward {
		type filter hook forward priority filter; policy drop;
		iifname { "eth1" } oifname { "eth2" } meta l4proto icmp counter packets 12 bytes 1008 accept comment "rule 10"
		iifname { "eth1" } oifname { "eth2" } tcp dport { 80, 443 } counter packets 3 bytes 180 accept comment "rule 20"
		counter packets 5 bytes 420 drop comment "default deny"
	}
}
X
fi
EOF
cat > "$T/bin/conntrack" <<'EOF'
#!/bin/bash
echo "tcp      6 431999 ESTABLISHED src=192.168.10.10 dst=203.0.113.10 sport=40000 dport=80 src=203.0.113.10 dst=203.0.113.1 sport=80 dport=40000 [ASSURED] mark=0 use=1"
echo "tcp      6 300 ESTABLISHED src=172.20.20.1 dst=172.20.20.5 sport=5555 dport=5000 src=172.20.20.5 dst=172.20.20.1 sport=5000 dport=5555 [ASSURED] mark=0 use=1"
echo "icmp     1 29 src=192.168.20.100 dst=203.0.113.10 type=8 code=0 id=7 src=203.0.113.10 dst=203.0.113.1 type=0 code=0 id=7 mark=0 use=1"
EOF
printf '#!/bin/bash\n[ $# -eq 0 ] && echo FW1\nexit 0\n' > "$T/bin/hostname"
chmod +x "$T/bin/"*

export T PATH="$T/bin:$PATH" NETLAB_LIB="$T/lib" NETLAB_RUN="$T/run" NETLAB_SYSNET="$T/sys" NETLAB_FW_STARTUP="$T/fw.conf"
FW="$ROOT/images/linux-fw/fw"

pass=0; fail=0
run() { OUT=$(bash "$FW" "$@" 2>&1); RC=$?; [ "${VERBOSE:-0}" = 1 ] && { echo "----- fw $*"; echo "$OUT"; }; }
has() {
    if grep -qF -- "$2" <<<"$OUT"; then pass=$((pass + 1)); echo "PASS  $1"
    else fail=$((fail + 1)); echo "FAIL  $1"; echo "      expected: $2"; echo "$OUT" | sed 's/^/      | /'; fi
}
hasnt() {
    if grep -qF -- "$2" <<<"$OUT"; then fail=$((fail + 1)); echo "FAIL  $1 (must not contain: $2)"; echo "$OUT" | sed 's/^/      | /'
    else pass=$((pass + 1)); echo "PASS  $1"; fi
}
nft_has() { OUT=$(cat "$T/last.nft"); has "$@"; }

# ---- boot: load the phase1 startup config
run --load-startup
[ "$RC" = 0 ] && { pass=$((pass + 1)); echo "PASS  phase1 startup config loads without errors"; } || { fail=$((fail + 1)); echo "FAIL  startup config: $OUT"; }
nft_has "nft: icmp rule"      'iifname { "eth1" } oifname { "eth2" } meta l4proto icmp counter accept comment "rule 10"'
nft_has "nft: web rule"       'iifname { "eth1" } oifname { "eth2" } tcp dport { 80, 443 } counter accept comment "rule 20"'
nft_has "nft: dns rule"       'udp dport { 53 } counter accept comment "rule 30"'
nft_has "nft: default deny"   'counter drop comment "default deny"'
nft_has "nft: masquerade"     'oifname { "eth2" } masquerade comment "nat outside"'
nft_has "nft: mgmt isolated"  'iifname "eth0" drop comment "management is never routed"'
nft_has "nft: stateful"       'ct state established,related accept'
grep -q "ip addr add 10.0.34.2/30 dev eth1" "$T/ip.log" && { pass=$((pass + 1)); echo "PASS  address applied"; } || { fail=$((fail + 1)); echo "FAIL  address applied"; }
grep -q "ip route replace default via 10.0.34.1 proto static" "$T/ip.log" && { pass=$((pass + 1)); echo "PASS  route applied"; } || { fail=$((fail + 1)); echo "FAIL  route applied"; cat "$T/ip.log"; }

# ---- CLI commands
run -c "show running-config"
has "show run hostname first" "hostname FW1"
has "show run has rule 30"    "rule 30 permit udp from inside to outside port 53"

run -c "rule 15 deny tcp from inside to outside port 23"
run -c "show run"
first_rule=$(grep -n '^rule 10 ' <<<"$OUT" | cut -d: -f1); new_rule=$(grep -n '^rule 15 ' <<<"$OUT" | cut -d: -f1); next_rule=$(grep -n '^rule 20 ' <<<"$OUT" | cut -d: -f1)
if [ -n "$new_rule" ] && [ "$first_rule" -lt "$new_rule" ] && [ "$new_rule" -lt "$next_rule" ]; then pass=$((pass + 1)); echo "PASS  rule 15 sorted between 10 and 20"; else fail=$((fail + 1)); echo "FAIL  rule order"; echo "$OUT"; fi
nft_has "nft: deny rule"      'tcp dport { 23 } counter drop comment "rule 15"'

run -c "rule 15 deny tcp from 192.168.20.0/24 to any port 22"
run -c "show run"
has "rule replaced"           "rule 15 deny tcp from 192.168.20.0/24 to any port 22"
hasnt "old rule gone"         "rule 15 deny tcp from inside to outside port 23"
nft_has "nft: prefix source"  'ip saddr 192.168.20.0/24 tcp dport { 22 } counter drop comment "rule 15"'

run -c "no rule 15"
run -c "show run"
hasnt "no rule removes"       "rule 15"
run -c "no rule 99"
has "no unknown rule"         "'rule 99' is not in the configuration"

run -c "rule 40 permit icmp from inside to outside port 80"
has "port needs tcp/udp"      "a port can only be used with tcp or udp"
run -c "rule 40 permit foo from inside to outside"
has "bad protocol"            "usage: rule <seq> permit|deny"
run -c "interface eth0 address 1.2.3.4/24"
has "eth0 protected"          "eth0 is the management interface"
run -c "interface eth1 zone Inside"
has "zone lowercase"          "usage: interface <ethN> zone <name>"
run -c "route 10.0.0.0/33 via 10.0.34.1"
has "bad prefix"              "usage: route <a.b.c.d/nn|default> via <gateway>"
run -c "frobnicate"
has "unknown command"         "unknown command 'frobnicate'"

run -c "rule 50 permit any from dmz to outside"
nft_has "unknown zone skipped" "# rule 50 skipped: zone 'dmz' has no interfaces"
run -c "no rule 50"

NFT_FAIL=1 run -c "rule 60 permit icmp from any to any"
has "rejected change reported" "change rejected, previous configuration restored"
run -c "show run"
hasnt "rejected change undone" "rule 60"

run -c "show rules"
has "show rules header"       "Seq    Action  Proto  Source             Destination        Port          Hits"
has "show rules hits"         "10     permit  icmp   inside             outside            -             12"
has "show rules port"         "20     permit  tcp    inside             outside            80,443        3"
has "show rules default"      "5  (default)"

run -c "show interfaces"
has "show interfaces zone"    "eth1       inside"

run -c "show conn"
has "show conn nat"           "192.168.10.10:40000"
has "show conn nat target"    "src -> 203.0.113.1"
hasnt "show conn hides mgmt"  "172.20.20.1"

run -c "write"
has "write ok"                "[OK]"
grep -q "^rule 30 permit udp" "$T/fw.conf" && { pass=$((pass + 1)); echo "PASS  write saved the startup config"; } || { fail=$((fail + 1)); echo "FAIL  write"; }

printf 'hostname X\nrule 5 permit tcp from any to any port 99999\ninterface eth9 address 10.9.9.1/24\n' > "$T/bad.conf"
NETLAB_FW_STARTUP="$T/bad.conf" run --load-startup
has "startup error line"      "line 2: usage: rule"
has "missing interface warn"  "eth9 does not exist on this node"

echo
echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
