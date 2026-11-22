#!/bin/bash
# lab.sh - start, stop and inspect NetLab labs (inside the NetLab WSL distro, as root).
#
#   lab.sh list                    labs you can deploy (and which ones are running)
#   lab.sh plan     <lab>          images present? estimated RAM vs free RAM
#   lab.sh deploy   <lab>          start the lab, then print boot times and consoles
#   lab.sh destroy  <lab>          stop the lab and remove its containers
#   lab.sh status   <lab>          containerlab inspect
#   lab.sh consoles <lab>          telnet / SSH ports of every node
#   lab.sh nodes    <lab>          node list for scripts (tab separated)
#   lab.sh test     <lab>          run the lab's connectivity tests (tests.conf)
#   lab.sh report   <lab>          boot time and live CPU/RAM per node
#
# Lab templates live in /opt/netlab/labs/<lab>/ (copied from the Windows project
# folder). A deploy copies the template to /var/lib/netlab/labs/<lab>/ and runs
# it there, so the running lab never depends on files on the Windows drive.
set -uo pipefail
source "$(dirname "$0")/lib.sh"
require_root

TOPO_PY="$NETLAB/wsl/netlab_topo.py"

lab_src() { echo "$NETLAB/labs/$1"; }
lab_run() { echo "$STATE/labs/$1"; }
topo_in() { ls "$1"/*.clab.yml 2>/dev/null | head -n1; }

# The topology to use: the running copy if the lab was deployed, else the template.
topo_of() {
    local t
    t=$(topo_in "$(lab_run "$1")")
    [ -n "$t" ] || t=$(topo_in "$(lab_src "$1")")
    [ -n "$t" ] || die "lab '$1' not found in $NETLAB/labs"
    echo "$t"
}

lab_name()    { python3 "$TOPO_PY" name "$1"; }
is_running()  { [ -n "$(docker ps -q --filter "label=containerlab=$1" 2>/dev/null)" ]; }
container_of() { echo "clab-$1-$2"; }

# --------------------------------------------------------------------- list
cmd_list() {
    local d name state
    for d in "$NETLAB"/labs/*/; do
        name=$(basename "$d")
        [ -n "$(topo_in "$d")" ] || continue
        state="stopped"
        is_running "$(lab_name "$(topo_in "$d")")" && state="RUNNING"
        printf '%-12s %-8s %s\n' "$name" "$state" "$(sed -n 's/^# *Description: *//p' "$(topo_in "$d")" | head -n1)"
    done
}

# --------------------------------------------------------------------- plan
# Prints KEY=value lines (the Windows menu reads them) and human messages.
cmd_plan() {
    local lab=$1 topo missing=() img need avail margin vm
    load_images_env
    topo=$(topo_in "$(lab_src "$lab")") || true
    [ -n "$topo" ] || die "lab '$lab' not found"
    while read -r img; do
        docker image inspect "$img" >/dev/null 2>&1 || missing+=("$img")
    done < <(python3 "$TOPO_PY" images "$topo")

    need=$(python3 "$TOPO_PY" estimate "$topo" "$NETLAB/config/settings.json" "$NETLAB/config/settings.default.json")
    margin=$(setting '.ram.safetyMarginMB' 512)
    avail=$(awk '/^MemAvailable:/ {print int($2 / 1024)}' /proc/meminfo)
    # Nodes that are full virtual machines (QEMU, e.g. Cisco ASAv) need GBs of RAM each.
    vm=$(python3 "$TOPO_PY" nodes "$topo" | awk -F'\t' -v k=" $(setting '.ram.vmKinds | join(" ")' cisco_asav) " \
        'index(k, " " $2 " ") {n++} END {print n + 0}')
    echo "NODES=$(python3 "$TOPO_PY" nodes "$topo" | wc -l)"
    echo "VM_NODES=$vm"
    echo "NEED_MB=$need"
    echo "WSL_AVAILABLE_MB=$avail"
    echo "MARGIN_MB=$margin"
    echo "MISSING_IMAGES=${missing[*]:-}"
    if [ ${#missing[@]} -gt 0 ]; then
        warn "missing images: ${missing[*]}"
        for img in "${missing[@]}"; do
            case $img in
                vrnetlab/cisco_iol:*) echo "      -> import your Cisco IOL / IOL-L2 image first (menu: Import IOL image)" ;;
                netlab/*)             echo "      -> build the NetLab images first (wsl/build-images.sh)" ;;
            esac
        done
    fi
    if [ "$vm" -gt 0 ]; then
        warn "$vm node(s) are full virtual machines (e.g. ASAv): each one needs several GB of RAM"
    fi
    if [ "$need" -gt $((avail - margin)) ]; then
        warn "the lab needs about $need MB but WSL has only $avail MB available (keeping $margin MB spare)"
    fi
}

# ------------------------------------------------------------------- deploy
cmd_deploy() {
    local lab=$1 src run topo name workers t0 t1
    src=$(lab_src "$lab"); run=$(lab_run "$lab")
    [ -n "$(topo_in "$src")" ] || die "lab '$lab' not found in $NETLAB/labs"
    docker_ready || die "Docker is not running"
    load_images_env

    name=$(lab_name "$(topo_in "$src")")
    is_running "$name" && die "lab '$name' is already running (destroy it first)"

    local plan
    plan=$(cmd_plan "$lab" 2>&1)
    grep -q '^MISSING_IMAGES=.' <<<"$plan" && { echo "$plan" | grep -v '='; die "cannot deploy: images are missing"; }

    rm -rf "$run"
    mkdir -p "$(dirname "$run")"
    cp -a "$src" "$run"
    topo=$(topo_in "$run")
    workers=$(max_workers)

    info "Deploying lab '$name' ($(python3 "$TOPO_PY" nodes "$topo" | wc -l) nodes, up to $workers in parallel)"
    t0=$(date +%s.%N)
    ( cd "$run" && containerlab deploy -t "$topo" --max-workers "$workers" ) || die "containerlab deploy failed"
    t1=$(date +%s.%N)
    echo "$t0" > "$run/.deploy-start"
    ok "containerlab finished in $(awk -v a="$t0" -v b="$t1" 'BEGIN {printf "%.1f", b - a}') s"

    cmd_boot_report "$lab" wait
    cmd_consoles "$lab"
}

# Boot time of each node: from container start until it is usable.
#   IOL:   the "Press RETURN to get started" line in its console log
#   Linux: the /run/netlab/ready file written by the node's init script
node_ready_epoch() {
    local c=$1 kind=$2 ts
    case $kind in
        cisco_iol)
            ts=$(docker logs -t "$c" 2>&1 | grep -a -m1 'Press RETURN to get started' | awk '{print $1}')
            [ -n "$ts" ] && date -d "$ts" +%s.%N ;;
        *)
            docker exec "$c" cat /run/netlab/ready 2>/dev/null ;;
    esac
}

cmd_boot_report() {
    local lab=$1 mode=${2:-} topo name node kind type img c started ready deadline all_ready
    topo=$(topo_of "$lab"); name=$(lab_name "$topo")
    deadline=$(( $(date +%s) + $(setting '.deploy.bootTimeoutS' 600) ))
    echo
    info "Boot times (container start -> node ready)"
    printf '  %-8s %-14s %-10s\n' "NODE" "KIND" "BOOT"
    {
        while IFS=$'\t' read -r node kind type img _ _; do
            c=$(container_of "$name" "$node")
            started=$(docker inspect -f '{{.State.StartedAt}}' "$c" 2>/dev/null) || { printf '  %-8s %-14s %s\n' "$node" "$kind" "not running"; continue; }
            started=$(date -d "$started" +%s.%N)
            ready=""
            while :; do
                ready=$(node_ready_epoch "$c" "$kind")
                [ -n "$ready" ] || [ "$mode" != wait ] || [ "$(date +%s)" -ge "$deadline" ] && break
                sleep 2
            done
            [ "$type" != "-" ] && kind="$kind/$type"
            if [ -n "$ready" ]; then
                printf '  %-8s %-14s %6.1f s\n' "$node" "$kind" "$(awk -v a="$started" -v b="$ready" 'BEGIN {print b - a}')"
            else
                printf '  %-8s %-14s %s\n' "$node" "$kind" "not ready yet"
            fi
        done < <(python3 "$TOPO_PY" nodes "$topo")
    } | tee "$(lab_run "$lab")/boot-report.txt"
    if [ "$mode" = wait ] && [ -f "$(lab_run "$lab")/.deploy-start" ]; then
        all_ready=$(date +%s.%N)
        echo "  Whole lab: deploy start -> all nodes checked: $(awk -v a="$(cat "$(lab_run "$lab")/.deploy-start")" -v b="$all_ready" 'BEGIN {printf "%.1f", b - a}') s" |
            tee -a "$(lab_run "$lab")/boot-report.txt"
    fi
}

# ------------------------------------------------------------------ destroy
cmd_destroy() {
    local lab=$1 topo
    topo=$(topo_of "$lab")
    info "Destroying lab '$(lab_name "$topo")'"
    ( cd "$(dirname "$topo")" && containerlab destroy -t "$topo" --cleanup ) || die "containerlab destroy failed"
    ok "lab stopped, memory released"
}

cmd_status() {
    local topo; topo=$(topo_of "$1")
    ( cd "$(dirname "$topo")" && containerlab inspect -t "$topo" )
}

cmd_nodes() { python3 "$TOPO_PY" nodes "$(topo_of "$1")"; }

# ----------------------------------------------------------------- consoles
cmd_consoles() {
    local lab=$1 topo node kind type img telnet ssh user
    topo=$(topo_of "$lab")
    echo
    info "Consoles (from Windows: PuTTY -> Telnet -> 127.0.0.1 + port)"
    printf '  %-8s %-14s %-24s %-24s %s\n' "NODE" "KIND" "CONSOLE (telnet)" "SSH" "LOGIN"
    while IFS=$'\t' read -r node kind type img telnet ssh; do
        case $kind in
            cisco_iol) user="admin / admin" ;;
            *)         user="root / netlab" ;;
        esac
        [ "$type" != "-" ] && kind="$kind/$type"
        printf '  %-8s %-14s %-24s %-24s %s\n' "$node" "$kind" \
            "$( [ "$telnet" != - ] && echo "127.0.0.1:$telnet" || echo -)" \
            "$( [ "$ssh" != - ] && echo "ssh -p $ssh $( [ "${kind%%/*}" = cisco_iol ] && echo admin || echo root)@127.0.0.1" || echo -)" \
            "$user"
    done < <(python3 "$TOPO_PY" nodes "$topo")
}

# --------------------------------------------------------------------- test
# tests.conf lines:  <node> <ping|noping|http|dns|dhcp> <target> <description...>
cmd_test() {
    local lab=$1 topo name file node action target desc c pass=0 fail=0 tries i okay t0
    topo=$(topo_of "$lab"); name=$(lab_name "$topo")
    file="$(dirname "$topo")/tests.conf"
    [ -f "$file" ] || die "this lab has no tests.conf"
    is_running "$name" || die "lab '$name' is not running"
    tries=$(setting '.tests.retries' 12)
    t0=$(date +%s)
    info "Connectivity tests for '$name' (each test retries up to $tries x 5 s while routing converges)"
    while read -r node action target desc; do
        [[ -z $node || $node == \#* ]] && continue
        c=$(container_of "$name" "$node")
        okay=0
        for ((i = 1; i <= tries; i++)); do
            case $action in
                ping)   docker exec "$c" ping -c 2 -W 2 "$target" >/dev/null 2>&1 && okay=1 ;;
                noping) docker exec "$c" ping -c 2 -W 2 "$target" >/dev/null 2>&1 || okay=1 ;;
                http)   [ "$(docker exec "$c" curl -s -m 5 -o /dev/null -w '%{http_code}' "http://$target/" 2>/dev/null)" = 200 ] && okay=1 ;;
                dns)    docker exec "$c" nslookup "$target" >/dev/null 2>&1 && okay=1 ;;
                dhcp)   docker exec "$c" test -f "/run/netlab/dhcp-$target.lease" && okay=1 ;;
                *)      warn "unknown test action '$action'"; break ;;
            esac
            [ "$okay" = 1 ] && break
            [ "$action" = noping ] && break          # a "must fail" test is not retried
            sleep 5
        done
        if [ "$okay" = 1 ]; then
            pass=$((pass + 1)); printf "  ${C_GRN}PASS${C_OFF}  %-6s %-7s %-16s %s\n" "$node" "$action" "$target" "$desc"
        else
            fail=$((fail + 1)); printf "  ${C_RED}FAIL${C_OFF}  %-6s %-7s %-16s %s\n" "$node" "$action" "$target" "$desc"
        fi
    done < "$file"
    echo "  $pass passed, $fail failed ($(( $(date +%s) - t0 )) s)"
    [ "$fail" = 0 ]
}

# ------------------------------------------------------------------- report
cmd_report() {
    local lab=$1 topo name out
    topo=$(topo_of "$lab"); name=$(lab_name "$topo")
    is_running "$name" || die "lab '$name' is not running"
    out="$STATE/reports/$name-$(date +%Y%m%d-%H%M%S).txt"
    mkdir -p "$STATE/reports"
    {
        echo "NetLab report for lab '$name' - $(date)"
        echo "Host: $(nproc) CPU threads, kernel $(uname -r)"
        cmd_boot_report "$lab"
        echo
        "$NETLAB/wsl/stats.sh" "$name"
    } | tee "$out"
    echo
    ok "saved to $out"
}

main() {
    local cmd=${1:-}
    case $cmd in
        list)                           cmd_list ;;
        plan|deploy|destroy|status|consoles|nodes|test|report)
            [ -n "${2:-}" ] || die "usage: lab.sh $cmd <lab>"
            "cmd_$cmd" "$2" ;;
        boot)                           cmd_boot_report "${2:?lab}" ;;
        *)  sed -n '2,14p' "$0"; exit 2 ;;
    esac
}
main "$@"
