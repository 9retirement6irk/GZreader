#!/system/bin/sh
# GZreader's helper for its Nook launcher icon (Nook 1st Edition).
#
# The icon (GZreader-launcher.apk) is an ordinary Android app: it can't run
# GZreader itself, which needs root (pausing Android, the screens, Wi-Fi),
# and the Nook's su lets only adb's shell and root use it. So this helper
# runs as root from the Nook's start-up and waits; the icon asks it to start
# GZreader by writing "start" into a pipe (launch/start) only it reads.
#
#   adb shell sh /data/gzreader/launcher.sh install     once: start it with
#        the Nook (one line added to /system/etc/bravo_pltinfo.sh, which the
#        Nook runs as root at every start) and now
#   adb shell sh /data/gzreader/launcher.sh uninstall   take that line out
#        and stop it
#   sh launcher.sh run                                  the helper itself
#
# Only "start" does anything; it starts GZreader if it isn't running.

GZ=${GZ:-/data/gzreader}
BB=${GZ_BUSYBOX:-$GZ/runtime/busybox}

# Android 1.5's shell is minimal: the rest runs in BusyBox's
if [ -z "$GZ_IN_BUSYBOX" ]; then
    chmod 755 $BB 2>/dev/null
    export GZ_IN_BUSYBOX=1
    exec $BB sh "$0" "$@"
fi
HOOK=${GZ_NOOK_BOOT_SCRIPT:-/system/etc/bravo_pltinfo.sh}
MARK="# GZreader launcher helper"
PIPE=$GZ/launch/start
PIDF=$GZ/launch/helper.pid
LOG=$GZ/launch/helper.log

log() { echo "$($BB date '+%F %T') $*" >> "$LOG"; }

running() {
    [ -f "$PIDF" ] && kill -0 "$($BB cat "$PIDF")" 2>/dev/null
}

start_helper() {
    running && return 0
    # (its own session: nothing that started it takes it down)
    $BB setsid $BB sh "$GZ/launcher.sh" run < /dev/null > /dev/null 2>&1 &
    $BB sleep 1
    running
}

stop_helper() {
    running && kill "$($BB cat "$PIDF")" 2>/dev/null
    $BB rm -f "$PIDF"
}

# The Nook's own /system/etc: while GZreader runs, its copy is mounted over
# it (for DNS: gzreader.sh), and a line added there wouldn't last.
nook_system_etc() {
    if $BB grep -q " /system/etc " "${GZ_MOUNTS:-/proc/mounts}" 2>/dev/null; then
        if $BB pidof luajit > /dev/null 2>&1; then
            echo "GZreader is running: choose Exit to Nook in GZreader first, then run this again."
            exit 1
        fi
        # (left over from a GZreader that didn't close properly)
        $BB umount /system/etc 2>/dev/null || umount /system/etc 2>/dev/null
    fi
}

remount() { $BB mount -o "remount,$1" /system 2>/dev/null || mount -o "remount,$1" /system 2>/dev/null; }

case "${1:-run}" in
install)
    [ "$($BB id -u)" = 0 ] || { echo "Run it as root: adb shell sh $GZ/launcher.sh install"; exit 1; }
    nook_system_etc
    [ -f "$HOOK" ] || { echo "$HOOK isn't there: this isn't a Nook 1st Edition with its own software?"; exit 1; }
    if ! $BB grep -q "^$MARK" "$HOOK"; then
        remount rw
        printf '\n%s (adb shell sh %s/launcher.sh uninstall takes it out)\n[ -f %s/launcher.sh ] && /system/bin/sh %s/launcher.sh start\n' \
            "$MARK" "$GZ" "$GZ" "$GZ" >> "$HOOK"
        remount ro
        $BB grep -q "^$MARK" "$HOOK" || { echo "Couldn't add the helper to $HOOK (is /system read-only?)."; exit 1; }
    fi
    if start_helper; then
        echo "GZreader's launcher helper runs (and starts with the Nook). Tap GZreader in the Nook's app list to start it."
    else
        echo "The helper didn't start: see $LOG."
        exit 1
    fi
    ;;
uninstall)
    nook_system_etc
    stop_helper
    if $BB grep -q "^$MARK" "$HOOK" 2>/dev/null; then
        remount rw
        # (the mark line and the one after it)
        $BB sed -i "/^$MARK/{N;d;}" "$HOOK"
        remount ro
    fi
    $BB rm -f "$PIPE"
    echo "GZreader's launcher helper is off and no longer starts with the Nook."
    ;;
start)
    start_helper
    ;;
run)
    # Nothing it was started with stays open: adb's shell hands its children
    # its own connection on many descriptors (3, 7-30 on a Nook), and adb
    # waits for every copy to close, so "install" never returned.
    fd=3
    while [ $fd -lt 64 ]; do eval "exec $fd>&-" 2>/dev/null; fd=$((fd + 1)); done
    [ -x "$BB" ] || chmod 755 "$BB"
    $BB mkdir -p "$GZ/launch"
    # the icon (an app, not root) must reach the pipe: through the folders,
    # and write it
    chmod 755 "$GZ" "$GZ/launch"
    [ -p "$PIPE" ] || { $BB rm -f "$PIPE"; $BB mkfifo "$PIPE"; }
    chmod 622 "$PIPE"
    echo $$ > "$PIDF"
    log "helper waiting (pid $$)"
    # (open for reading and writing: never at end of file, an icon's write never waits)
    exec 3<> "$PIPE"
    while read -r line <&3; do
        [ "$line" = start ] || continue
        if $BB pidof luajit > /dev/null 2>&1; then
            log "start asked: GZreader is already running"
            continue
        fi
        log "start asked: starting GZreader"
        GZ_IN_BUSYBOX= $BB sh "$GZ/gzreader.sh" < /dev/null > /dev/null 2>&1
        log "GZreader closed ($?)"
        # taps on the icon while it ran (or just before): not another start
        while read -r -t 1 line <&3; do :; done
    done
    log "helper stopped"
    ;;
*)
    echo "Usage: sh $GZ/launcher.sh install | uninstall"
    exit 1
    ;;
esac
