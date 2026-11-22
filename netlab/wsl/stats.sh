#!/bin/bash
# stats.sh - live CPU and RAM of every node of a running lab, plus totals.
#
#   stats.sh <lab-name>
#
# RAM is what Docker reports per container (cgroup memory minus page cache
# that can be dropped). Pages of the same IOL binary are shared between
# routers and counted only once on the host.
source "$(dirname "$0")/lib.sh"
require_root
lab=${1:?usage: stats.sh <lab-name>}

ids=$(docker ps -q --filter "label=containerlab=$lab")
[ -n "$ids" ] || die "lab '$lab' is not running"

info "Per node (one sample)"
# shellcheck disable=SC2086
docker stats --no-stream --format '{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}' $ids |
    sed "s/^clab-$lab-//" | sort |
    awk -F'\t' '
        function mb(s,   n, u) {               # "215.3MiB" -> 215.3
            n = s; sub(/[A-Za-z]+$/, "", n); u = s; sub(/^[0-9.]+/, "", u)
            if (u == "GiB" || u == "GB") return n * 1024
            if (u == "KiB" || u == "kB") return n / 1024
            if (u == "B") return n / 1048576
            return n
        }
        BEGIN { printf "  %-8s %8s %10s\n", "NODE", "CPU", "RAM (MB)" }
        {
            split($3, m, " / "); ram = mb(m[1]); cpu = $2; sub(/%/, "", cpu)
            tot_ram += ram; tot_cpu += cpu
            printf "  %-8s %7.1f%% %10.1f\n", $1, cpu, ram
        }
        END { printf "  %-8s %7.1f%% %10.1f\n", "TOTAL", tot_cpu, tot_ram }'

echo
info "WSL virtual machine memory (MB)"
free -m | awk 'NR == 1 {printf "  %-6s %8s %8s %8s %10s\n", "", $1, $2, $3, $NF} NR == 2 {printf "  %-6s %8s %8s %8s %10s\n", $1, $2, $3, $4, $NF}'

if [ -r /sys/kernel/mm/ksm/run ]; then
    echo
    "$(dirname "$0")/ksm.sh" status
fi
