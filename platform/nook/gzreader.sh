#!/system/bin/sh
# GZreader on the Nook 1st Edition and the Nook Simple Touch (TEST BUILD).
#
# Run as root, e.g. from a computer:   adb shell sh /data/gzreader/gzreader.sh
# or from GZreader's icon on the Nook 1st Edition (launcher.sh: the Nook's su
# is for adb only, so a root helper starts it).
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
    echo "GZreader needs root: run it with adb shell (or from GZreader's icon: sh $GZ/launcher.sh install, once)."
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

RUN=$GZ/run
mkdir -p $RUN

# --- 1b. where the books go ------------------------------------------------
# Where the GZreader folder (books, audiobooks, downloads) goes: a microSD
# card when one is in and writable (more room), else the Nook's own storage
# (the 1st Edition's /system/media/sdcard, the Simple Touch's /media; GZreader
# tells the two Nooks apart by their screens). Both Nooks have their own
# storage on mmcblk0 and the card slot on mmcblk1 (vold's 179:8-15; a 1st
# Edition lists them as /dev/block//vold/179:3 and /dev/block//vold/179:9).
# GZ_NOOK_HOME overrides it.
MOUNTS=${GZ_MOUNTS:-/proc/mounts}
if [ -z "$GZ_NOOK_HOME" ]; then
    SD=$(awk '$1 ~ /^\/dev\/block\/+(vold\/179:(8|9|1[0-5])$|mmcblk1)/ && $3 ~ /^(vfat|msdos|fat)$/ && ("," $4 ",") ~ /,rw,/ { print $2; exit }' "$MOUNTS" 2>/dev/null)
    if [ -n "$SD" ] && mkdir -p "$SD/GZreader" 2>/dev/null && : > "$SD/GZreader/.gz-write-test" 2>/dev/null; then
        rm -f "$SD/GZreader/.gz-write-test"
        GZ_NOOK_HOME=$SD
        log "GZreader folder on the microSD card ($SD)"
    elif [ -d /sys/devices/platform/bravo-vfb ]; then GZ_NOOK_HOME=/system/media/sdcard
    elif [ -d /media ]; then GZ_NOOK_HOME=/media
    else GZ_NOOK_HOME=/sdcard
    fi
    # While the Nook is a USB drive on a computer, its storage isn't mounted
    # here: the folder would be an empty one on the root file system (books
    # written there vanish when the storage comes back, and fill the root).
    if ! awk -v d="$GZ_NOOK_HOME" '$2 == d { found = 1 } END { exit !found }' "$MOUNTS" 2>/dev/null; then
        log "the Nook's storage ($GZ_NOOK_HOME) isn't mounted: it's a USB drive on a computer"
        echo "The Nook's storage is in use as a USB drive: eject the Nook's drives on the computer, wait until"
        echo "the Nook shows its own screen again, then start GZreader. (GZreader keeps its books there.)"
        umount /system/etc 2>/dev/null
        exit 1
    fi
fi
export GZ_NOOK_HOME

# DNS: Android's servers (properties) in a resolv.conf, over /system/etc
# for as long as GZreader runs (a copy of it plus resolv.conf)
set_dns() {
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
}

# Wi-Fi: Android keeps it, but when its screen went off it switched Wi-Fi off
# (B&N's wifi_stop: eth0 down, the chip unpowered), and paused it can't turn
# it back on: GZreader's setup said "Error connecting to network". So, when
# there's no connection, it's brought up as Android does: B&N's wifi_start
# (powers the chip: /sys/power/wifi_pm, eth0 up; the Marvell chip takes a few
# seconds to appear), wpa_supplicant with the networks saved on the
# Nook, dhcpcd for an address. Taken down again on exit (Android left it
# off). GZ_NOOK_WIFI=off leaves Wi-Fi alone.
WIFI_STARTED=
wifi_up() {
    netcfg 2>/dev/null | awk '$1 == "eth0" && $2 == "UP" && $3 != "0.0.0.0" { ok = 1 } END { exit !ok }'
}
wait_for() { # <seconds> <command...>
    n=$1; shift
    while [ "$n" -gt 0 ]; do "$@" && return 0; sleep 1; n=$((n - 1)); done
    return 1
}
dhcp_done() {
    [ "$(getprop dhcp.eth0.result)" = "ok" ] || wifi_up
}
start_wifi() {
    [ "$GZ_NOOK_WIFI" = "off" ] && return 0
    if wifi_up; then log "Wi-Fi: already connected"; return 0; fi
    log "Wi-Fi: off (Android switched it off), connecting"
    WIFI_STARTED=1
    # (B&N's wifi_start.sh, done here: init's services didn't run for us, so
    # wpa_supplicant and dhcpcd are started directly too, as init.rc has them)
    echo 1 > /sys/power/wifi_pm
    if ! wait_for 25 test -e /sys/class/net/eth0; then log "Wi-Fi: the chip didn't come up"; return 1; fi
    ifconfig eth0 up 2>/dev/null
    rm -f /data/misc/wifi/sockets/wpa_ctrl_* 2>/dev/null
    /system/bin/wpa_supplicant -Dwext -ieth0 -c/system/etc/wifi/wpa_supplicant.conf -B > $RUN/wpa.log 2>&1
    sleep 1
    WPA_PID=$(pidof wpa_supplicant)
    if [ -z "$WPA_PID" ]; then log "Wi-Fi: wpa_supplicant didn't start ($(head -c 200 $RUN/wpa.log | tr '\n' ' '))"; return 1; fi
    log "Wi-Fi: wpa_supplicant running"
    setprop dhcp.eth0.result ""
    /system/bin/dhcpcd -ABKL eth0 > $RUN/dhcpcd.log 2>&1 &
    DHCP_PID=$!
    if ! wait_for 45 dhcp_done; then
        log "Wi-Fi: no address (no saved network in reach?)"
        return 1
    fi
    if ! wifi_up; then
        # (as Android's NetworkUtils does with dhcpcd's answer)
        ifconfig eth0 "$(getprop dhcp.eth0.ipaddress)" netmask "$(getprop dhcp.eth0.mask)" up 2>/dev/null
        route add default gw "$(getprop dhcp.eth0.gateway)" dev eth0 2>/dev/null
    fi
    wifi_up && log "Wi-Fi: connected"
}
stop_wifi() {
    [ -n "$WIFI_STARTED" ] || return 0
    [ -n "$DHCP_PID" ] && kill "$DHCP_PID" 2>/dev/null
    for p in $(pidof dhcpcd) $(pidof wpa_supplicant); do kill "$p" 2>/dev/null; done
    # (B&N's wifi_stop.sh)
    ifconfig eth0 down 2>/dev/null
    echo 0 > /sys/power/wifi_pm
    WIFI_STARTED=
    log "Wi-Fi: off again, as Android left it"
}

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
# Awake: when Android turned its screen off it asked the kernel to sleep
# (early suspend: the colour screen's LCD controller stopped), and nothing
# would wake it now that Android is paused: the colour screen stayed black.
# (GZreader then lights it, and puts the Nook to sleep itself.)
echo on > /sys/power/state 2>/dev/null && log "kernel awake (early suspend undone)"
sleep 1
start_wifi
set_dns

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
    stop_wifi
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
