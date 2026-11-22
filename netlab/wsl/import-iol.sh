#!/bin/bash
# import-iol.sh - turns your own Cisco IOL image into a containerlab image with vrnetlab.
#
#   import-iol.sh <image-file> [--version 17.12.01] [--l2|--l3] [--backup-dir <dir>]
#
# Accepted files (as found in a Cisco Modeling Labs "refplat" ISO, incl. CML-Free):
#   - a raw IOL binary, e.g. x86_64_crb_linux-adventerprisek9-ms(.iol / .bin)
#     or the IOL-L2 one,    x86_64_crb_linux_l2-adventerprisek9-ms
#   - a CML 2.10+ archive, e.g. iol-xe-17-18-02.tar.gz / ioll2-xe-17-18-02.tar.gz
#
# The script detects L2 vs L3 and the IOS version, names the file the way
# vrnetlab expects, runs "make docker-image" and records the resulting image
# in /var/lib/netlab/images.env (NETLAB_IOL_IMAGE / NETLAB_IOL_L2_IMAGE).
# NetLab never downloads or bundles Cisco images.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_root
docker_ready || die "Docker is not running"

file="" version="" kind="" backup=""
while [ $# -gt 0 ]; do
    case $1 in
        --version)    version=$2; shift ;;
        --l2)         kind=L2 ;;
        --l3)         kind=L3 ;;
        --backup-dir) backup=$2; shift ;;
        -*)           die "unknown option $1" ;;
        *)            file=$1 ;;
    esac
    shift
done
[ -f "$file" ] || die "image file not found: $file"
[ -d /opt/vrnetlab/cisco/iol ] || die "vrnetlab is missing (run install-engine.sh)"

name=$(basename "$file")
lower=$(echo "$name" | tr 'A-Z' 'a-z')
magic=$(head -c 4 "$file" | od -An -tx1 | tr -d ' \n')

# ---------------------------------------------------------- what is it?
case $magic in
    7f454c46) format=bin ;;                      # ELF executable = raw IOL binary
    1f8b*)    format=targz ;;                    # gzip = CML 2.10+ archive
    *)        die "$name is neither an IOL binary (ELF) nor a .tar.gz archive" ;;
esac

if [ -z "$kind" ]; then
    case $lower in
        *ioll2*|*_l2*|*-l2*|*l2-*) kind=L2 ;;
        *) kind=L3 ;;
    esac
    # The binary itself says it: "...(X86_64BI_LINUX_L2-ADVENTERPRISEK9-M)..."
    if [ "$format" = bin ] && grep -a -q 'LINUX_L2-' "$file"; then kind=L2; fi
fi

if [ -z "$version" ]; then
    if [ "$format" = bin ]; then
        # e.g. "Version 17.12.1," -> 17.12.01
        v=$(grep -a -o -m1 'Version 1[0-9]\.[0-9]*\.[0-9A-Za-z]*' "$file" | head -n1 | awk '{print $2}' || true)
    else
        # e.g. iol-xe-17-18-02.tar.gz -> 17.18.02
        v=$(echo "$lower" | grep -o '[0-9]\+-[0-9]\+-[0-9a-z]\+' | head -n1 | tr '-' '.' || true)
    fi
    [ -n "$v" ] || die "could not detect the IOS version; pass it with --version 17.12.01"
    # 17.12.1 -> 17.12.01 (vrnetlab tags use two digits)
    version=$(echo "$v" | awk -F. '{ m = $3; if (m ~ /^[0-9][^0-9]*$/ || m ~ /^[0-9]$/) m = "0" m; print $1 "." $2 "." m }')
fi

tag=$version
[ "$kind" = L2 ] && tag="L2-$version"
image="vrnetlab/cisco_iol:$tag"
info "Detected: IOL $kind, version $version, format $format -> $image"

# ------------------------------------------------------------- build it
dir=/opt/vrnetlab/cisco/iol
rm -f "$dir"/*.bin "$dir"/*.tar.gz
if [ "$format" = bin ]; then
    if [ "$kind" = L2 ]; then dest="cisco_iol-L2-$version.bin"; else dest="cisco_iol-$version.bin"; fi
else
    dest=$name                                 # vrnetlab reads the name as-is
fi
cp "$file" "$dir/$dest"
info "Building with vrnetlab (make docker-image). The first build downloads a"
info "small Go toolchain image and takes a few minutes."
start=$(date +%s)
( cd "$dir" && make docker-image )
rm -f "$dir/$dest"

docker image inspect "$image" >/dev/null 2>&1 || die "build finished but $image was not found (see the make output above)"
ok "Built $image in $(( $(date +%s) - start )) s"

# ------------------------------------------------- remember the image tag
var=NETLAB_IOL_IMAGE
[ "$kind" = L2 ] && var=NETLAB_IOL_L2_IMAGE
touch "$IMAGES_ENV"
sed -i "/^$var=/d" "$IMAGES_ENV"
echo "$var=$image" >> "$IMAGES_ENV"
ok "Labs will now use $image ($var in $IMAGES_ENV)"

# Free the build cache (the Go toolchain layers); the image itself stays.
docker builder prune -f >/dev/null 2>&1 || true

if [ -n "$backup" ]; then
    mkdir -p "$backup"
    cp -n "$file" "$backup/" && ok "Original image backed up to $backup"
fi
# A copy that the Windows importer dropped into "incoming" is no longer needed.
case $(readlink -f "$file") in
    "$STATE"/incoming/*) rm -f "$file" ;;
esac
