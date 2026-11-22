#!/bin/bash
# ksm.sh - Kernel Samepage Merging (KSM): the kernel merges identical memory
# pages of different processes, so several similar VMs need less RAM.
#
#   ksm.sh status | on | off
#
# Good to know: KSM only scans memory that a program offers for merging.
# QEMU virtual machines (e.g. Cisco ASAv built with vrnetlab) do this, so KSM
# helps them a lot. IOL routers are normal Linux processes and do not offer
# their memory, so KSM saves little for IOL today; their program code is
# already shared because all routers run the same binary file.
source "$(dirname "$0")/lib.sh"
K=/sys/kernel/mm/ksm
[ -d "$K" ] || die "this kernel has no KSM support ($K missing)"

case ${1:-status} in
    on)
        require_root
        echo 1    > "$K/run"
        echo 200  > "$K/sleep_millisecs"    # scan gently: 200 ms pause between batches
        echo 1000 > "$K/pages_to_scan"
        ok "KSM enabled" ;;
    off)
        require_root
        echo 2 > "$K/run"                   # 2 = stop and un-merge everything
        ok "KSM disabled" ;;
    status)
        page=$(getconf PAGESIZE)
        sharing=$(cat "$K/pages_sharing")
        state=$(cat "$K/run")
        case $state in 0) state=off ;; 1) state=on ;; 2) state="off (unmerged)" ;; esac
        info "KSM: $state, saving about $(( sharing * page / 1048576 )) MB (pages_sharing=$sharing)" ;;
    *)
        die "usage: ksm.sh status|on|off" ;;
esac
