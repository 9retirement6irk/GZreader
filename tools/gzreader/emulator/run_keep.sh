#!/bin/bash
# Like run.sh, but keeps the install's settings, history and library (for
# start-up timings after a setup run): run_keep.sh <script.lua> <outdir>
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
TREE=${GZ_EMU_TREE:-/root/work/emu/koreader}
SCRIPT=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
OUT=$(mkdir -p "$2" && cd "$2" && pwd)
cd "$TREE" || exit 1
rm -rf "${OUT:?}"/*
cp "$TREE/koreader.sh" /var/tmp/koreader.sh
timeout "${EMU_TIMEOUT:-400}" qemu-arm-static -L /usr/arm-linux-gnueabi ./luajit "$HERE/emu.lua" "$SCRIPT" "$OUT" > "$OUT.txt" 2>&1
echo "exit $?  (log: $OUT.txt)"
