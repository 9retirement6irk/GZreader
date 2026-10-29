#!/bin/bash
# Start the live emulator in the background (fresh install unless KEEP=1).
#   start_live.sh [cpu percent]   -> GZ_EMU_OUT (default /root/work/emu/live)
HERE=$(cd "$(dirname "$0")" && pwd)
TREE=${GZ_EMU_TREE:-/root/work/emu/koreader}
OUT=${GZ_EMU_OUT:-/root/work/emu/live}
mkdir -p "$OUT"
[ -f "$OUT/emu.pid" ] && kill "$(cat "$OUT/emu.pid")" 2>/dev/null
cd "$TREE" || exit 1
if [ -z "${KEEP:-}" ]; then
    rm -rf "$OUT"/* settings.reader.lua settings.reader.lua.old settings defaults.persistent.lua* history.lua* \
        gzreader-remote cache history docsettings gzreader.log /mnt/us/GZreader
fi
mkdir -p /mnt/us/documents "$OUT"
cp "$TREE/koreader.sh" /var/tmp/koreader.sh
(
    if [ -n "${1:-}" ]; then
        CG=/sys/fs/cgroup/cpu/gz-kindle
        mkdir -p $CG && echo 100000 > $CG/cpu.cfs_period_us && echo $(( $1 * 1000 )) > $CG/cpu.cfs_quota_us && echo $BASHPID > $CG/cgroup.procs
    fi
    exec setsid qemu-arm-static -L /usr/arm-linux-gnueabi ./luajit "$HERE/emu.lua" "$HERE/live.lua" "$OUT" > "$OUT/emu.txt" 2>&1
) &
echo $! > "$OUT/emu.pid"
echo "started pid $(cat "$OUT/emu.pid"), output in $OUT"
