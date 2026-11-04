#!/usr/bin/env bash
# The Linux basics GZreader needs on a Nook 1st Edition (Android 1.5 has
# its own C library, not glibc): Debian 7 "wheezy" armel's glibc (2.13,
# built for Linux 2.6.26 and later: the Nook runs 2.6.27), libgcc and a
# static BusyBox, from Debian's archive, checked against its package index.
# (GZreader's binaries are the Kindle 2/3/DX build's: ARMv6, glibc 2.4 ABI.)
#
# Usage: tools/gzreader/nook-runtime.sh <out-dir>
#   <out-dir>/lib/      ld-linux.so.3, libc.so.6, libm, libpthread, librt, libdl,
#                       libresolv, libnss_dns, libnss_files, libgcc_s.so.1
#   <out-dir>/busybox   (static)
#   <out-dir>/SOURCES.txt  what came from where (versions, checksums)
set -euo pipefail

OUT=$(mkdir -p "${1:?out dir}" && cd "$1" && pwd)
MIRROR=${DEBIAN_ARCHIVE:-https://archive.debian.org/debian}
DIST=wheezy
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

curl -fsSL "$MIRROR/dists/$DIST/main/binary-armel/Packages.gz" | gunzip > "$WORK/Packages"

# fetch <package>: download its .deb (checked against the index) and unpack it
fetch() {
    local pkg=$1 file sha
    file=$(awk -v p="$pkg" '$1=="Package:"{cur=$2} cur==p && $1=="Filename:"{print $2; exit}' "$WORK/Packages")
    sha=$(awk -v p="$pkg" '$1=="Package:"{cur=$2} cur==p && $1=="SHA256:"{print $2; exit}' "$WORK/Packages")
    [ -n "$file" ] && [ -n "$sha" ] || { echo "no $pkg in $DIST armel" >&2; exit 1; }
    curl -fsSL -o "$WORK/$pkg.deb" "$MIRROR/$file"
    echo "$sha  $WORK/$pkg.deb" | sha256sum -c --quiet
    mkdir -p "$WORK/$pkg"
    dpkg-deb -x "$WORK/$pkg.deb" "$WORK/$pkg"
    echo "$pkg  $(basename "$file")  sha256 $sha" >> "$OUT/SOURCES.txt"
}

: > "$OUT/SOURCES.txt"
fetch libc6
fetch libgcc1
fetch busybox-static

mkdir -p "$OUT/lib"
L="$WORK/libc6/lib/arm-linux-gnueabi"
[ -d "$L" ] || L="$WORK/libc6/lib"
cp -L "$WORK/libc6/lib/ld-linux.so.3" "$OUT/lib/ld-linux.so.3"
for f in libc.so.6 libm.so.6 libpthread.so.0 librt.so.1 libdl.so.2 libresolv.so.2 libnss_dns.so.2 libnss_files.so.2 libutil.so.1; do
    cp -L "$L/$f" "$OUT/lib/$f"
done
G="$WORK/libgcc1/lib/arm-linux-gnueabi"
[ -d "$G" ] || G="$WORK/libgcc1/lib"
cp -L "$G/libgcc_s.so.1" "$OUT/lib/libgcc_s.so.1"
cp -L "$WORK/busybox-static/bin/busybox" "$OUT/busybox"
chmod 755 "$OUT/busybox" "$OUT"/lib/*
cat >> "$OUT/SOURCES.txt" <<TXT

From $MIRROR (Debian $DIST, armel). glibc and libgcc are LGPL / GPL with the
runtime exception, BusyBox is GPL-2.0: their sources are in the same archive
(pool/main/e/eglibc, pool/main/g/gcc-4.7, pool/main/b/busybox).
TXT
ls -la "$OUT" "$OUT/lib"
