#!/usr/bin/env bash
# GZreader for the Nook 1st Edition and Nook Simple Touch (TEST BUILD), from the Kindle 2/3/DX
# package (same processor family, ARMv6: its binaries run on the Nook too)
# plus the Linux basics the Nook lacks (tools/gzreader/nook-runtime.sh) and
# the Nook's start script.
#
# Usage: tools/gzreader/package-nook.sh <gzreader-kindle-legacy-X.zip> <runtime-dir> [out-dir]
# Output: gzreader-nook-<version>.zip with one folder, gzreader/, to copy to
# /data/gzreader on the Nook (see GZREADER.md, "Nook 1st Edition").
set -euo pipefail

SRC_ZIP=${1:?gzreader-kindle-legacy-X.zip}
RUNTIME=${2:?runtime dir from nook-runtime.sh}
OUT_DIR=$(mkdir -p "${3:-.}" && cd "${3:-.}" && pwd)
REPO=$(cd "$(dirname "$0")/../.." && pwd)
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

GZ_VERSION=${GZ_VERSION:-$(tr -d ' \n' < "$REPO/GZREADER_VERSION")}
[ -x "$RUNTIME/busybox" ] && [ -f "$RUNTIME/lib/ld-linux.so.3" ] || { echo "no runtime in $RUNTIME" >&2; exit 1; }

unzip -q "$SRC_ZIP" -d "$STAGE/src"
G="$STAGE/gzreader"
mkdir -p "$G"
mv "$STAGE/src/koreader" "$G/koreader"
KO="$G/koreader"
# Kindle-only parts
rm -f "$KO/fbink" "$KO/koreader.sh" "$KO/libkohelper.sh" "$KO/wmctrl"
rm -rf "$KO/frontend/device/kindle"
cp -r "$RUNTIME" "$G/runtime"
rm -f "$G/runtime/SOURCES.txt"
cp "$RUNTIME/SOURCES.txt" "$G/runtime-SOURCES.txt" 2>/dev/null || true
cp "$REPO/platform/nook/gzreader.sh" "$G/gzreader.sh"
chmod 755 "$G/gzreader.sh" "$KO/luajit"
cat > "$G/README-NOOK.txt" <<TXT
GZreader $GZ_VERSION for the Nook ${GZ_NOOK_FOR:-1st Edition and Nook Simple Touch} - TEST BUILD

Copy this folder to /data/gzreader on a rooted Nook, then start it as root:
    adb push gzreader /data/gzreader
    adb shell sh /data/gzreader/gzreader.sh
Choose Exit in GZreader to go back to the Nook's own software.

Full steps (rooting, installing, what to try, what to send back):
https://github.com/9retirement6irk/GZreader/blob/main/GZREADER.md#nook-1st-edition-test-build
https://github.com/9retirement6irk/GZreader/blob/main/GZREADER.md#nook-simple-touch-test-build
TXT

# (GZ_NOOK_NAME=gzreader-nook-1st-edition: the build without VFP, gzreader-nook.yml)
OUT="$OUT_DIR/${GZ_NOOK_NAME:-gzreader-nook}-${GZ_VERSION}.zip"
rm -f "$OUT"
(cd "$STAGE" && zip -qr -9 "$OUT" gzreader)
echo "$OUT"
du -h "$OUT"
