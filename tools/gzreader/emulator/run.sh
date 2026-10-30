#!/bin/bash
# Run GZreader as a Kindle 3 under qemu-arm (see README.md).
#   run.sh <script.lua> <outdir> [cpu percent, e.g. 20 ≈ a Kindle 3]
# Env: GZ_EMU_TREE (default /root/work/emu/koreader), EMU_TIMEOUT (s, default 400)
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
TREE=${GZ_EMU_TREE:-/root/work/emu/koreader}
SCRIPT=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
OUT=$(mkdir -p "$2" && cd "$2" && pwd)
cd "$TREE" || exit 1
# a fresh install every time (LuaSettings also restores from *.old)
rm -rf "$OUT"/* settings.reader.lua settings.reader.lua.old settings defaults.persistent.lua* history.lua* \
    gzreader-remote gzreader-usage cache history docsettings gzreader.log /mnt/us/GZreader
mkdir -p /mnt/us/documents
cp "$TREE/koreader.sh" /var/tmp/koreader.sh # else: "startup script has been updated"
if [ -n "${3:-}" ]; then
    CG=/sys/fs/cgroup/cpu/gz-kindle
    mkdir -p $CG && echo 100000 > $CG/cpu.cfs_period_us && echo $(( $3 * 1000 )) > $CG/cpu.cfs_quota_us && echo $$ > $CG/cgroup.procs
fi
timeout "${EMU_TIMEOUT:-400}" qemu-arm-static -L /usr/arm-linux-gnueabi ./luajit "$HERE/emu.lua" "$SCRIPT" "$OUT" > "$OUT.txt" 2>&1
echo "exit $?  (log: $OUT.txt, screens: $OUT/*.png, GZreader log: $TREE/gzreader.log)"
