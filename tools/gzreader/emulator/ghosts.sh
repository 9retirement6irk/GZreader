#!/bin/bash
# setsid -w ghosts.sh <outdir>: run ghosts.lua, then start GZreader again (as the
# Kindle's launcher does after a restart) with ghosts_after.lua, all in one
# process session, and list what's left of that session afterwards.
# Needs the demo Grimmory on 127.0.0.1:18080 and a stand-in gst-launch-0.10.
OUT=$1; E=/root/work/emu; T=/root/work/koreader/tools/gzreader/emulator
export GZ_SID=$(ps -o sid= -p $$ | tr -d ' ')
cd $E && bash run.sh $T/ghosts.lua $OUT > /dev/null
cd $E/koreader
EMU_TIMEOUT=120 timeout 120 qemu-arm-static -L /usr/arm-linux-gnueabi ./luajit ../emu.lua $T/ghosts_after.lua $OUT-after > $OUT-after.txt 2>&1
sleep 3
echo "== left in the session after GZreader quit =="
ps -e -o pid=,ppid=,etimes=,sid=,args= | awk -v s="$GZ_SID" '$4==s' | grep -v " ps -e\| awk \|ghosts.sh\|sleep 3$" | cut -c1-150
