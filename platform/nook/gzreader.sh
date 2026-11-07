#!/system/bin/sh
# GZreader on the Nook 1st Edition and the Nook Simple Touch (TEST BUILD).
#
# Run as root, e.g. from a computer:   adb shell sh /data/gzreader/gzreader.sh
# or in a terminal app on the Nook:    su -c "sh /data/gzreader/gzreader.sh"
#
# What it does, and undoes when GZreader closes:
#  1. gives GZreader's Linux programs what they expect on a Linux system:
#     /lib/ld-linux.so.3 (GZreader's own C library, in runtime/lib),
#     /bin/sh (BusyBox) and a resolv.conf for DNS (Android keeps its DNS
#     servers in properties);
#  2. pauses Android's interface (SIGSTOP: B&N's reading app and the system
#     server), so it doesn't draw over GZreader; Wi-Fi keeps running;
#  3. runs GZreader (koreader/) until you choose Exit, restarting it when it
#     asks to (after an update);
#  4. resumes Android, which redraws its screens.
# The changes to / are on the Nook's RAM disk: a restart undoes them too.

GZ=${GZ:-/data/gzreader}
RT=$GZ/runtime
BB=$RT/busybox

# Android 1.5's shell is minimal: run the rest with BusyBox's
if [ -z "$GZ_IN_BUSYBOX" ]; then
    chmod 755 $BB 2>/dev/null
    export GZ_IN_BUSYBOX=1
    exec $BB sh "$0" "$@"
fi

# (BusyBox's commands first: Android 1.5's own are few and different)
$BB mkdir -p $RT/bin && $BB --install -s $RT/bin 2>/dev/null
export PATH=$RT/bin:$PATH

LOG=$GZ/gzreader-start.log
log() { echo "$(date '+%F %T') $*" >> "$LOG"; echo "$*"; }
: > "$LOG"

if [ "$(id -u)" != "0" ]; then
    echo "GZreader needs root: run it with adb shell, or su -c \"sh $0\" in a terminal."
    exit 1
fi
if [ ! -x "$GZ/koreader/luajit" ] && [ ! -f "$GZ/koreader/luajit" ]; then
    echo "GZreader isn't in $GZ (expected $GZ/koreader/luajit)."
    exit 1
fi

# --- 1. a Linux system's basics -------------------------------------------
chmod 755 "$GZ/koreader/luajit" "$GZ/koreader/sdcv" "$GZ/koreader/tar" $RT/lib/* 2>/dev/null
mount -o remount,rw / 2>/dev/null
mkdir -p /lib /bin
for f in $RT/lib/*; do
    [ -e "/lib/${f##*/}" ] || ln -s "$f" "/lib/${f##*/}"
done
[ -e /bin/sh ] || ln -s $BB /bin/sh
[ -e /bin/busybox ] || ln -s $BB /bin/busybox
$BB --install -s /bin 2>/dev/null
mount -o remount,ro / 2>/dev/null

# DNS: Android's servers (properties) in a resolv.conf, over /system/etc
# for as long as GZreader runs (a copy of it plus resolv.conf)
RUN=$GZ/run
mkdir -p $RUN
umount /system/etc 2>/dev/null
rm -rf $RUN/etc
mkdir -p $RUN/etc
cp -a /system/etc/. $RUN/etc/ 2>/dev/null
: > $RUN/etc/resolv.conf
for p in net.dns1 net.dns2 dhcp.eth0.dns1 dhcp.eth0.dns2 dhcp.tiwlan0.dns1 dhcp.wlan0.dns1; do
    ip=$(getprop $p 2>/dev/null)
    case "$ip" in
        [0-9]*) grep -q "nameserver $ip\$" $RUN/etc/resolv.conf || echo "nameserver $ip" >> $RUN/etc/resolv.conf ;;
    esac
done
[ -s $RUN/etc/resolv.conf ] || echo "nameserver 1.1.1.1" > $RUN/etc/resolv.conf
grep -q localhost $RUN/etc/hosts 2>/dev/null || echo "127.0.0.1 localhost" >> $RUN/etc/hosts
mount -o bind $RUN/etc /system/etc && log "DNS: $(tr '\n' ' ' < $RUN/etc/resolv.conf)"

# --- 2. pause Android's interface ----------------------------------------
: > $RUN/stopped
ZYGOTE=$(pidof zygote)
if [ -n "$ZYGOTE" ]; then
    for d in /proc/[0-9]*; do
        pid=${d#/proc/}
        ppid=$(cut -d' ' -f4 "$d/stat" 2>/dev/null)
        if [ "$ppid" = "$ZYGOTE" ]; then
            kill -STOP "$pid" 2>/dev/null && echo "$pid" >> $RUN/stopped
        fi
    done
    kill -STOP "$ZYGOTE" && echo "$ZYGOTE" >> $RUN/stopped
fi
log "paused Android: $(wc -l < $RUN/stopped) processes"

# Unaligned memory accesses: the 1st Edition's kernel stops a program that
# makes one ("User faults: 4 (signal)" in /proc/cpu/alignment: exit code
# 135, Bus error). GZreader's Nook build avoids them; any left are fixed up
# by the kernel (2, without logging each one: logging them froze the Nook)
# while GZreader runs, and the Nook's own setting comes back afterwards.
ALIGN_OLD=
if [ -w /proc/cpu/alignment ]; then
    ALIGN_OLD=$(sed -n 's/^User faults:[[:space:]]*\([0-9]\).*/\1/p' /proc/cpu/alignment)
    ALIGN_START=$(sed -n 's/^User:[[:space:]]*\([0-9]*\).*/\1/p' /proc/cpu/alignment)
    echo 2 > /proc/cpu/alignment && log "unaligned accesses: fixed up (the Nook's setting: ${ALIGN_OLD:-?})"
fi
restore_alignment() {
    [ -n "$ALIGN_OLD" ] || return 0
    n=$(sed -n 's/^User:[[:space:]]*\([0-9]*\).*/\1/p' /proc/cpu/alignment)
    log "unaligned accesses fixed up while GZreader ran: $(( ${n:-0} - ${ALIGN_START:-0} ))"
    echo "$ALIGN_OLD" > /proc/cpu/alignment
    ALIGN_OLD=
}

resume_android() {
    restore_alignment
    umount /system/etc 2>/dev/null
    if [ -s $RUN/stopped ]; then
        while read -r pid; do kill -CONT "$pid" 2>/dev/null; done < $RUN/stopped
        : > $RUN/stopped
        log "resumed Android"
    fi
}
trap 'resume_android; exit 1' INT TERM HUP

# --- 3. GZreader -----------------------------------------------------------
cd "$GZ/koreader" || exit 1
# (GZreader tells the two Nooks apart by their screens; their own storage:
# the 1st Edition's /system/media/sdcard, the Simple Touch's /media)
if [ -z "$GZ_NOOK_HOME" ]; then
    if [ -d /sys/devices/platform/bravo-vfb ]; then GZ_NOOK_HOME=/system/media/sdcard
    elif [ -d /media ]; then GZ_NOOK_HOME=/media
    else GZ_NOOK_HOME=/sdcard
    fi
fi
export GZ_NOOK_HOME
export PATH=/bin:$PATH
export LC_ALL=en_US.UTF-8
export STARDICT_DATA_DIR=data/dict
export EXT_FONT_DIR="/system/fonts;$GZ_NOOK_HOME/fonts"
export HOME=$GZ_NOOK_HOME
mkdir -p "$GZ_NOOK_HOME/GZreader" 2>/dev/null
RETURN_VALUE=85
while [ "$RETURN_VALUE" -eq 85 ]; do
    ./luajit ./reader.lua "$@" >> crash.log 2>&1
    RETURN_VALUE=$?
    log "GZreader exited with $RETURN_VALUE"
    sync
done

# --- 4. back to Android ------------------------------------------------------
resume_android
exit 0
