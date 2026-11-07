#!/bin/sh

export LC_ALL="en_US.UTF-8"

# Compute our working directory in an extremely defensive manner
SCRIPT_DIR="$(CDPATH='' cd "$(dirname "$0")" && pwd -P)"
# NOTE: We need to remember the *actual* KOREADER_DIR, not the relocalized version in /tmp...
export KOREADER_DIR="${KOREADER_DIR:-${SCRIPT_DIR}}"
UNPACK_DIR="${KOREADER_DIR%/*}"

# NOTE: Stupid workaround to make sure the script we end up running is a *copy*,
# living in a magical land that doesn't suffer from gross filesystem deficiencies.
# Otherwise, the vfat+fuse mess means an OTA update will break the script on exit,
# and potentially leave the user in a broken state, with the WM still paused...
# Additionally, this is used by KOReader to detect if the original script has
# changed after an update (requiring a complete restart from the parent
# launcher).
if [ "$(dirname "${0}")" != "/var/tmp" ]; then
    cp -pf "${0}" /var/tmp/koreader.sh
    chmod 777 /var/tmp/koreader.sh
    exec /var/tmp/koreader.sh "$@"
fi

# We rely on starting from our working directory, and it needs to be set, sane and absolute.
cd "${KOREADER_DIR:-/dev/null}" || exit

PROC_KEYPAD="/proc/keypad"
PROC_FIVEWAY="/proc/fiveway"
[ -e "${PROC_KEYPAD}" ] && echo unlock >"${PROC_KEYPAD}"
[ -e "${PROC_FIVEWAY}" ] && echo unlock >"${PROC_FIVEWAY}"

# NOTE: Same vfat+fuse shenanigans needed for FBInk, before we source libko...
cp -pf "${KOREADER_DIR}/fbink" /var/tmp/fbink
chmod 777 /var/tmp/fbink

# Load our helper functions...
if [ -f "${KOREADER_DIR}/libkohelper.sh" ]; then
    # shellcheck source=/dev/null
    . "${KOREADER_DIR}/libkohelper.sh"
else
    echo "Can't source helper functions, aborting!"
    exit 1
fi

# Handle logging...
logmsg() {
    # Use the right tools for the platform
    if [ "${INIT_TYPE}" = "sysv" ]; then
        msg "koreader: ${1}" "I"
    elif [ "${INIT_TYPE}" = "upstart" ]; then
        f_log I koreader wrapper "" "${1}"
    fi

    # And throw that on stdout too, for the DIY crowd ;)
    echo "${1}"
}

# Go away if we're on FW 5.0, it's not supported
if [ "${INIT_TYPE}" = "upstart" ]; then
    if grep '^Kindle 5\.0' /etc/prettyversion.txt >/dev/null 2>&1; then
        logmsg "FW 5.0 is not supported. Update to 5.1!"
        # And... scene!
        exit 0
    fi
fi

# Keep track of what we do with pillow...
export STOP_FRAMEWORK="no"
export AWESOME_STOPPED="no"
export CVM_STOPPED="no"
export VOLUMD_STOPPED="no"
PILLOW_HARD_DISABLED="no"
PILLOW_SOFT_DISABLED="no"
USED_WMCTRL="no"
PASSCODE_DISABLED="no"

# List of services we stop in order to reclaim a tiny sliver of RAM...
TOGGLED_SERVICES="stored webreader kfxreader kfxview todo tmd rcm archive scanner otav3 otaupd"

REEXEC_FLAGS=""
# Keep track of if we were started through KUAL
if [ "${1}" = "--kual" ]; then
    shift 1
    FROM_KUAL="yes"
    REEXEC_FLAGS="${REEXEC_FLAGS} --kual"
else
    FROM_KUAL="no"
    export EIPS_NO_SLEEP="yes"
fi

# By default, don't stop the framework.
if [ "${1}" = "--framework_stop" ]; then
    shift 1
    STOP_FRAMEWORK="yes"
    NO_SLEEP="no"
    REEXEC_FLAGS="${REEXEC_FLAGS} --framework_stop"
elif [ "${1}" = "--asap" ]; then
    # Start as soon as possible, without sleeping to workaround UI quirks
    shift 1
    NO_SLEEP="yes"
    REEXEC_FLAGS="${REEXEC_FLAGS} --asap"
    export EIPS_NO_SLEEP="yes"
else
    NO_SLEEP="no"
fi

# If we were started by KUAL (either Kindlet or Booklet), we have a few more things to do...
if [ "${FROM_KUAL}" = "yes" ]; then
    # Yield a bit to let stuff stop properly...
    logmsg "Hush now . . ."
    if [ "${NO_SLEEP}" = "no" ]; then
        # NOTE: This may or may not be terribly useful...
        usleep 250000
    fi

    # If we were started by the KUAL Kindlet, and not the Booklet, we have a nice value to correct...
    if [ "$(nice)" = "5" ]; then
        # Kindlet threads spawn with a nice value of 5, go back to a neutral value
        logmsg "Be nice!"
        renice -n -5 $$
    fi
fi

# we're always starting from our working directory
cd "${KOREADER_DIR}" || exit

# Handle pending OTA update
ko_update_check() {
    NEWUPDATE="${KOREADER_DIR}/ota/koreader.updated.tar"
    INSTALLED="${KOREADER_DIR}/ota/koreader.installed.tar"
    if [ -f "${NEWUPDATE}" ]; then
        logmsg "Updating GZreader . . ."
        # Let our checkpoint script handle the detailed visual feedback...
        eips_print_bottom_centered "Updating GZreader" 3
        # Keep a copy of the old manifest for cleaning leftovers later.
        cp "${KOREADER_DIR}/ota/package.index" /tmp/
        # Setup the FBInk daemon
        export FBINK_NAMED_PIPE="/tmp/koreader.fbink"
        rm -f "${FBINK_NAMED_PIPE}"
        FBINK_PID="$(/var/tmp/fbink --daemon 1 %KOREADER% -q -y -6 -P 0)"
        # NOTE: See frontend/ui/otamanager.lua for a few more details on how we squeeze a percentage out of tar's checkpoint feature
        # NOTE: %B should always be 512 in our case, so let stat do part of the maths for us instead of using %s ;).
        FILESIZE="$(stat -c %b "${NEWUPDATE}")"
        BLOCKS="$((FILESIZE / 20))"
        export CPOINTS="$((BLOCKS / 100))"
        # NOTE: To avoid blowing up when tar truncates itself during an update, copy our GNU tar binary to the system's tmpfs,
        #       and run that one (c.f., #4602)...
        #       This is most likely a side-effect of the weird fuse overlay being used for /mnt/us (vs. the real vfat on /mnt/base-us),
        #       which we cannot use because it's been mounted noexec for a few years now...
        cp -pf "${KOREADER_DIR}/tar" /var/tmp/gnutar
        # shellcheck disable=SC2016
        /var/tmp/gnutar --no-same-permissions --no-same-owner --checkpoint="${CPOINTS}" --checkpoint-action=exec='printf "%s" $((TAR_CHECKPOINT / CPOINTS)) > ${FBINK_NAMED_PIPE}' -C "${UNPACK_DIR}" -xf "${NEWUPDATE}"
        fail=$?
        kill -TERM "${FBINK_PID}"
        # And remove our temporary tar binary...
        rm -f /var/tmp/gnutar
        # Cleanup behind us...
        if [ "${fail}" -eq 0 ]; then
            mv "${NEWUPDATE}" "${INSTALLED}"
            # Cleanup leftovers from previous install.
            (cd "${UNPACK_DIR}" && grep -xvFf "${KOREADER_DIR}/ota/package.index" /tmp/package.index | xargs -r rm -vf)
            logmsg "Update successful :)"
            eips_print_bottom_centered "Update successful :)" 2
            eips_print_bottom_centered "GZreader will start momentarily . . ." 1
            # NOTE: Because, yep, that'll probably happen, as there's a high probability sh will throw a bogus syntax error,
            #       probably for the same fuse-related reasons as tar...
            # NOTE: Even if it doesn't necessarily leave the device in an unusable state,
            #       always recommend a hard-reboot to flush stale ghost copies...
            eips_print_bottom_centered "If it doesn't, you'll want to force a hard reboot" 0
        else
            # Huh ho...
            logmsg "Update failed :( (${fail})"
            eips_print_bottom_centered "Update failed :(" 2
            eips_print_bottom_centered "GZreader may fail to function properly" 1
        fi
        rm -f /tmp/package.index "${NEWUPDATE}" # always purge newupdate to prevent update loops
        unset CPOINTS FBINK_NAMED_PIPE
        unset BLOCKS FILESIZE FBINK_PID
        # Ensure everything is flushed to disk before we restart. This *will* stall for a while on slow storage!
        sync
    fi
}
# NOTE: Keep doing an initial update check, in addition to one during the restart loop, so we can pickup potential updates of this very script...
ko_update_check
# If an update happened, and was successful, reexec
if [ -n "${fail}" ] && [ "${fail}" -eq 0 ]; then
    # By now, we know we're in the right directory, and our script name is pretty much set in stone, so we can forgo using $0
    # NOTE: REEXEC_FLAGS *needs* to be unquoted: we *want* word splitting here ;).
    # shellcheck disable=SC2086
    exec ./koreader.sh ${REEXEC_FLAGS} "${@}"
fi

# export dict directory
export STARDICT_DATA_DIR="data/dict"

# export external font directories (In order: stock, stock custom (both legacy & 5.9.6+), stock extra, font hack)
export EXT_FONT_DIR="/usr/java/lib/fonts;/mnt/us/fonts;/var/local/font/mnt;/mnt/us/linkfonts/fonts"

# Only setup IPTables on devices where it makes sense to do so (FW 5.x & K4)
if [ "${INIT_TYPE}" = "upstart" ] || [ "$(uname -r)" = "2.6.31-rt11-lab126" ]; then
    logmsg "Setting up IPTables rules . . ."
    # accept input ports for calibre companion
    iptables -A INPUT -i wlan0 -p udp --dport 8134 -j ACCEPT
fi

# check if we need to disable the system passcode, because it messes with us in fun and interesting (and, more to the point, intractable) ways...
# NOTE: The most egregious one being that it inhibits the outOfScreenSaver event on wakeup until the passcode is validated, which we can't do, since we capture all input...
if [ -f "/var/local/system/userpasswdenabled" ]; then
    logmsg "Disabling system passcode . . ."
    rm -f "/var/local/system/userpasswdenabled"
    PASSCODE_DISABLED="yes"
fi

# check if we are supposed to shut down the Amazon framework
if [ "${STOP_FRAMEWORK}" = "yes" ]; then
    logmsg "Stopping the framework . . ."
    # Upstart or SysV?
    if [ "${INIT_TYPE}" = "sysv" ]; then
        /etc/init.d/framework stop
    else
        # The framework job sends a SIGTERM on stop, trap it so we don't get killed if we were launched by KUAL
        trap "" TERM
        stop lab126_gui
        # NOTE: Let the framework teardown finish, so we don't start before the black screen...
        usleep 1250000
        # And remove the trap like a ninja now!
        trap - TERM
    fi
fi

# Normalize a version string for easy numeric comparisons
# c.f., https://stackoverflow.com/a/37939589
version() { echo "$@" | awk -F. '{ printf("%d%03d%03d\n", $1,$2,$3); }'; }

# Detect kernels w/ CLOEXEC support
if [ "$(version "$(uname -r | sed -n -r 's/^([[:digit:]\.]*)(.*?)$/\1/p')")" -lt "$(version "2.6.23")" ]; then
    export KINDLE_LEGACY="yes"
fi

# There's no pillow if we stopped the framework, and it's only there on systems with upstart anyway
if [ "${STOP_FRAMEWORK}" = "no" ] && [ "${INIT_TYPE}" = "upstart" ]; then
    # NOTE: If we were launched from KUAL, don't even try to deal with KPVBooklet-specific workarounds
    if [ "${FROM_KUAL}" = "yes" ]; then
        kpv_launch_count="0"
    else
        kpv_launch_count="$(lipc-get-prop -eiq com.github.koreader.kpvbooklet.timer count)"
    fi
    # Check if KPVBooklet was launched more than once, if not we will disable pillow
    # c.f., https://github.com/koreader/koreader/commit/60f83e842ccce57931cbed5ffcebb28515f6f5d7
    if [ "${kpv_launch_count}" = "" ] || [ "${kpv_launch_count}" = "0" ]; then
        # NOTE: Dump the fb so we can restore something useful on exit...
        cat /dev/fb0 >/var/tmp/koreader-fb.dump
        # We're going to need our current FW version...
        FW_VERSION="$(grep '^Kindle 5' /etc/prettyversion.txt 2>&1 | sed -n -r 's/^(Kindle)([[:blank:]]*)([[:digit:]\.]*)(.*?)$/\3/p')"
        # NOTE: We want to disable the status bar (at the very least). Unfortunately, the soft hide/unhide method doesn't work properly anymore since FW 5.6.5...
        if [ "$(version "${FW_VERSION}")" -ge "$(version "5.6.5")" ]; then
            export PILLOW_HARD_DISABLED="yes"
            # FIXME: So we resort to killing pillow completely on FW >= 5.6.5...
            logmsg "Disabling pillow . . ."
            lipc-set-prop com.lab126.pillow disableEnablePillow disable
            # NOTE: And, oh, joy, on FW >= 5.7.2, this is not enough to prevent the clock from refreshing, so, take the bull by the horns, and SIGSTOP the WM while we run...
            if [ "$(version "${FW_VERSION}")" -ge "$(version "5.7.2")" ]; then
                # Less drastically, we'll also be "minimizing" (actually, resizing) the title bar manually (c.f., https://www.mobileread.com/forums/showpost.php?p=2449275&postcount=5).
                # NOTE: Hiding it "works", but has a nasty side-effect of triggering ligl timeouts in some circumstances (c.f., https://github.com/koreader/koreader/pull/5943#issuecomment-598514376)
                # FIXME: There's apparently a nasty side-effect on FW >= 5.12.4 which somehow softlocks the UI on exit (despite wmctrl succeeding). Don't have the HW to investigate, so, just drop it. (#6117)
                if [ "$(version "${FW_VERSION}")" -lt "$(version "5.12.4")" ]; then
                    logmsg "Hiding the title bar . . ."
                    TITLEBAR_GEOMETRY="$("${KOREADER_DIR}/wmctrl" -l -G | grep ":titleBar_ID:" | awk '{print $2,$3,$4,$5,$6}' OFS=',')"
                    "${KOREADER_DIR}/wmctrl" -r ":titleBar_ID:" -e "${TITLEBAR_GEOMETRY%,*},1"
                    logmsg "Title bar geometry: '${TITLEBAR_GEOMETRY}' -> '$("${KOREADER_DIR}/wmctrl" -l -G | grep ":titleBar_ID:" | awk '{print $2,$3,$4,$5,$6}' OFS=',')'"
                    USED_WMCTRL="yes"
                fi
                logmsg "Stopping awesome . . ."
                killall -STOP awesome
                AWESOME_STOPPED="yes"
            fi
        else
            logmsg "Hiding the status bar . . ."
            # NOTE: One more great find from eureka (http://www.mobileread.com/forums/showpost.php?p=2454141&postcount=34)
            lipc-set-prop com.lab126.pillow interrogatePillow '{"pillowId": "default_status_bar", "function": "nativeBridge.hideMe();"}'
            export PILLOW_SOFT_DISABLED="yes"
        fi
        # NOTE: We don't need to sleep at all if we've already SIGSTOPped awesome ;)
        if [ "${NO_SLEEP}" = "no" ] && [ "${AWESOME_STOPPED}" = "no" ]; then
            # NOTE: Leave the framework time to refresh the screen, so we don't start before it has finished redrawing after collapsing the title bar
            usleep 250000
            # NOTE: If we were started from KUAL, we risk getting a list item to popup right over us, so, wait some more...
            # The culprit appears to be a I WindowManager:flashTimeoutExpired:window=Root 0 0 600x30
            if [ "${FROM_KUAL}" = "yes" ]; then
                logmsg "Playing possum to wait for the window manager . . ."
                usleep 2500000
            fi
        fi

        # Murder a few services to reclaim some RAM...
        for job in ${TOGGLED_SERVICES}; do
            stop "${job}"
        done
    fi
fi

# stop cvm (sysv & framework up only)
if [ "${STOP_FRAMEWORK}" = "no" ] && [ "${INIT_TYPE}" = "sysv" ]; then
    logmsg "Stopping cvm . . ."
    killall -STOP cvm
    CVM_STOPPED="yes"
fi

# SIGSTOP volumd, to inhibit USBMS (sysv & upstart)
if [ -e "/etc/init.d/volumd" ] || [ -e "/etc/upstart/volumd.conf" ]; then
    logmsg "Stopping volumd . . ."
    killall -STOP volumd
    VOLUMD_STOPPED="yes"
fi

# finally call reader
logmsg "Starting GZreader . . ."
# That's not necessary when using KPVBooklet ;).
if [ "${FROM_KUAL}" = "yes" ]; then
    eips_print_bottom_centered "Starting GZreader . . ." 1
fi

# GZreader: what the last "Sync with computer" step-aside went through (kept
# in /var/local so a reboot doesn't lose it), into the crash log
if [ -s /var/local/gzreader-usb.log ]; then
    {
        echo "===== last USB drive step-aside ====="
        tail -n 60 /var/local/gzreader-usb.log
        gz_boot_then=$(sed -n 's/.* boot \([^,]*\), up.*/\1/p' /var/local/gzreader-usb.log | head -n 1)
        if [ -n "${gz_boot_then}" ]; then
            if [ "${gz_boot_then}" = "$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)" ]; then
                echo "(the Kindle hasn't restarted since; up $(cut -d' ' -f1 /proc/uptime 2>/dev/null) s)"
            else
                echo "(the Kindle restarted since: up $(cut -d' ' -f1 /proc/uptime 2>/dev/null) s)"
            fi
        fi
    } >>crash.log 2>/dev/null
fi
rm -f /var/local/gzreader-usb.log

# we keep at most 500KB worth of crash log
if [ -e crash.log ]; then
    tail -c 500000 crash.log >crash.log.new
    mv -f crash.log.new crash.log
fi

RETURN_VALUE=85
while [ "${RETURN_VALUE}" -eq 85 ]; do
    # Do an update check now, so we can actually update KOReader via the "Restart KOReader" menu entry ;).
    ko_update_check

    ./reader.lua "$@" >>crash.log 2>&1
    RETURN_VALUE=$?
done

# clean up our own process tree in case the reader crashed (if needed, to avoid flooding KUAL's log)
if pidof reader.lua >/dev/null 2>&1; then
    logmsg "Sending a SIGTERM to stray KOreader processes . . ."
    killall -TERM reader.lua
fi

# GZreader: stepping aside for the USB drive (exit 86) with the framework
# stopped (firmware 2.x/3.x): volumd stays paused until the framework that
# starts below has finished booting. Resumed at once, it shares the drive
# with the computer (the cable is usually in already) while the framework is
# still starting, and a Kindle DX then restarted over and over when the
# drive was ejected. See the step-aside below.
GZ_VOLUMD_LATER="no"
if [ "${RETURN_VALUE}" -eq 86 ] && [ "${VOLUMD_STOPPED}" = "yes" ] && [ "${STOP_FRAMEWORK}" = "yes" ] && [ "${INIT_TYPE}" = "sysv" ]; then
    GZ_VOLUMD_LATER="yes"
fi

# Resume volumd, if need be
if [ "${VOLUMD_STOPPED}" = "yes" ] && [ "${GZ_VOLUMD_LATER}" = "no" ]; then
    logmsg "Resuming volumd . . ."
    killall -CONT volumd
fi

# Resume cvm (only if we stopped it)
if [ "${STOP_FRAMEWORK}" = "no" ] && [ "${INIT_TYPE}" = "sysv" ]; then
    logmsg "Resuming cvm . . ."
    killall -CONT cvm
    # We need to handle the screen refresh ourselves, frontend/device/kindle/device.lua's Kindle3.exit is called before we resume cvm ;).
    echo 'send 139' >/proc/keypad
    echo 'send 139' >/proc/keypad
fi

# GZreader: say in crash.log how GZreader ended and how the Kindle's own
# interface came back (the diagnostic log shows it)
echo "GZreader: exited with ${RETURN_VALUE} (Kindle interface stopped: ${STOP_FRAMEWORK}, ${INIT_TYPE}) at $(date)" >>"${KOREADER_DIR}/crash.log" 2>/dev/null

# GZreader: stepping aside for the USB drive (exit 86): what GZreader wrote
# reaches the drive before it goes to the computer (a DX came back with its
# settings file corrupted)
if [ "${RETURN_VALUE}" -eq 86 ]; then
    sync
fi

# Restart framework (if need be)
if [ "${STOP_FRAMEWORK}" = "yes" ]; then
    logmsg "Restarting framework . . ."
    if [ "${INIT_TYPE}" = "sysv" ]; then
        cd / && /etc/init.d/framework start
    else
        cd / && start lab126_gui
    fi
    echo "GZreader: Kindle interface start asked: $? at $(date)" >>"${KOREADER_DIR}/crash.log" 2>/dev/null
fi

# Display chrome bar if need be (upstart & framework up only)
if [ "${STOP_FRAMEWORK}" = "no" ] && [ "${INIT_TYPE}" = "upstart" ]; then
    # Resume the services we murdered
    for job in ${TOGGLED_SERVICES}; do
        start "${job}"
    done

    # Depending on the FW version, we may have handled things in a few different manners...
    if [ "${AWESOME_STOPPED}" = "yes" ]; then
        logmsg "Resuming awesome . . ."
        killall -CONT awesome
    fi
    if [ "${PILLOW_HARD_DISABLED}" = "yes" ]; then
        logmsg "Enabling pillow . . ."
        # NOTE: Try to leave the user with a slightly more useful FB content than our own last screen...
        cat /var/tmp/koreader-fb.dump >/dev/fb0
        rm -f /var/tmp/koreader-fb.dump
        lipc-set-prop com.lab126.pillow disableEnablePillow enable
        lipc-set-prop com.lab126.appmgrd start app://com.lab126.booklet.home
    fi
    if [ "${PILLOW_SOFT_DISABLED}" = "yes" ]; then
        logmsg "Restoring the status bar . . ."
        # NOTE: Try to leave the user with a slightly more useful FB content than our own last screen...
        cat /var/tmp/koreader-fb.dump >/dev/fb0
        rm -f /var/tmp/koreader-fb.dump
        lipc-set-prop com.lab126.pillow interrogatePillow '{"pillowId": "default_status_bar", "function": "nativeBridge.showMe();"}'
        lipc-set-prop com.lab126.appmgrd start app://com.lab126.booklet.home
    fi
    if [ "${USED_WMCTRL}" = "yes" ]; then
        logmsg "Restoring the title bar . . ."
        # NOTE: Wait and retry for a bit, because apparently there may be timing issues (c.f., #5990)?
        usleep 250000
        WMCTRL_COUNT=0
        until [ "$("${KOREADER_DIR}/wmctrl" -l -G | grep ":titleBar_ID:" | awk '{print $2,$3,$4,$5,$6}' OFS=',')" = "${TITLEBAR_GEOMETRY}" ]; do
            # Abort after 5s
            if [ ${WMCTRL_COUNT} -gt 20 ]; then
                log "Giving up on restoring the title bar geometry!"
                break
            fi
            "${KOREADER_DIR}/wmctrl" -r ":titleBar_ID:" -e "${TITLEBAR_GEOMETRY}"
            usleep 250000
            WMCTRL_COUNT=$((WMCTRL_COUNT + 1))
        done
        logmsg "Title bar geometry restored to '$("${KOREADER_DIR}/wmctrl" -l -G | grep ":titleBar_ID:" | awk '{print $2,$3,$4,$5,$6}' OFS=',')' (ought to be: '${TITLEBAR_GEOMETRY}') [after ${WMCTRL_COUNT} attempts]"
    fi
fi

if [ "${INIT_TYPE}" = "upstart" ] || [ "$(uname -r)" = "2.6.31-rt11-lab126" ]; then
    logmsg "Restoring IPTables rules . . ."
    # restore firewall rules
    iptables -D INPUT -i wlan0 -p udp --dport 8134 -j ACCEPT
fi

if [ "${PASSCODE_DISABLED}" = "yes" ]; then
    logmsg "Restoring system passcode . . ."
    touch "/var/local/system/userpasswdenabled"
fi

# GZreader: Sync with computer (exit code 86). The Kindle's drive can only be
# shared over USB while nothing runs from it: GZreader lives on it, so it
# keeps volumd (the Kindle's USB drive service) stopped while it runs. It
# asked to step aside: volumd runs again (above), so plugging the Kindle in
# (or the cable that's in already) starts the Kindle's own USB drive mode.
# This script runs from a copy in /var/tmp, not from the drive, so it waits:
# once the drive has been shared and is back (ejected, unplugged), GZreader
# starts again and takes in what the computer brought. No USB mode within 15
# minutes: it stops waiting (start GZreader as usual).
# The framework runs again first (above): on firmware 2.x it's what hands the
# drive to the computer (a Kindle DX without it unmounted the drive and the
# computer never saw it).
gz_drive_here() {
    grep -qE " /mnt/(base-)?us " /proc/mounts
}
# (a trace of the step-aside, outside the drive: the next start puts it in crash.log)
gz_usb_log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') ${1}" >>/var/local/gzreader-usb.log 2>/dev/null
}
# Processes that still use the drive (it can't be shared while they do). The
# kernel on the Kindle 2/DX has no close-on-exec, so anything GZreader
# started inherited its open files (crash.log among them): GZreader's own
# leftovers (holding files in its folder) are stopped; the others are listed.
gz_drive_users() {
    for gz_p in /proc/[0-9]*; do
        gz_pid="${gz_p#/proc/}"
        [ "${gz_pid}" = "$$" ] && continue
        gz_on=$(ls -l "${gz_p}/cwd" "${gz_p}/exe" "${gz_p}/fd" 2>/dev/null | grep -E -- "-> /mnt/(base-)?us(/|$)")
        [ -n "${gz_on}" ] || continue
        gz_cmd=$(tr '\000' ' ' <"${gz_p}/cmdline" 2>/dev/null | cut -c1-80)
        if echo "${gz_on}" | grep -q -- "-> /mnt/us/koreader/"; then
            kill "${gz_pid}" 2>/dev/null
            gz_usb_log "stopped GZreader leftover ${gz_pid}: ${gz_cmd}"
        else
            gz_usb_log "uses the drive: ${gz_pid}: ${gz_cmd}"
        fi
    done
}
# Has the framework finished booting? Its Java VM (cvm) works flat out while
# it starts: booted once it has been there 45 s and used under half a second
# of CPU in each of two 5 s spells. At most 4 minutes (then: go on anyway).
gz_framework_settled() {
    gz_fw_t=0
    gz_fw_calm=0
    gz_fw_last=""
    gz_fw_seen=""
    gz_fw_cpu=""
    while [ ${gz_fw_t} -lt 240 ]; do
        sleep 5
        gz_fw_t=$((gz_fw_t + 5))
        gz_cvm=$(pidof cvm 2>/dev/null | awk '{print $1}')
        if [ -z "${gz_cvm}" ]; then
            gz_fw_last=""
            gz_fw_calm=0
            gz_fw_seen=""
            gz_fw_cpu="${gz_fw_cpu} -"
            continue
        fi
        [ -n "${gz_fw_seen}" ] || gz_fw_seen=${gz_fw_t}
        gz_fw_ticks=$(awk '{print $14 + $15}' "/proc/${gz_cvm}/stat" 2>/dev/null)
        if [ -n "${gz_fw_last}" ] && [ -n "${gz_fw_ticks}" ]; then
            gz_fw_cpu="${gz_fw_cpu} $((gz_fw_ticks - gz_fw_last))"
            if [ $((gz_fw_ticks - gz_fw_last)) -lt 50 ]; then gz_fw_calm=$((gz_fw_calm + 1)); else gz_fw_calm=0; fi
        else
            gz_fw_cpu="${gz_fw_cpu} ?"
            gz_fw_calm=0
        fi
        gz_fw_last="${gz_fw_ticks}"
        # (calm twice in a row, and cvm there for 45 s: a DX framework takes over a minute)
        if [ ${gz_fw_calm} -ge 2 ] && [ $((gz_fw_t - gz_fw_seen)) -ge 45 ]; then
            gz_usb_log "the Kindle interface is up (after ${gz_fw_t} s; cvm CPU per 5 s, 1/100 s:${gz_fw_cpu})"
            return 0
        fi
    done
    gz_usb_log "the Kindle interface still busy after ${gz_fw_t} s: going on (cvm CPU per 5 s, 1/100 s:${gz_fw_cpu})"
    return 1
}
# (only the latest of these waits goes on: a GZreader started meanwhile may ask again)
gz_latest_wait() {
    [ "$(cat /var/tmp/gzreader-usbwait 2>/dev/null)" = "$$" ]
}
if [ "${RETURN_VALUE}" -eq 86 ]; then
    cd / || true
    echo "$$" >/var/tmp/gzreader-usbwait
    rm -f /var/local/gzreader-usb.log
    gz_usb_log "stepping aside for the USB drive (${INIT_TYPE}, $(uname -r), Kindle interface stopped: ${STOP_FRAMEWORK})"
    # (which boot this is: the next start says whether the Kindle restarted
    # meanwhile; and who this wait belongs to)
    gz_usb_log "boot $(cat /proc/sys/kernel/random/boot_id 2>/dev/null), up $(cut -d' ' -f1 /proc/uptime 2>/dev/null) s; wait $$ (group $(awk '{print $5}' /proc/$$/stat 2>/dev/null)), started by $PPID: $(tr '\000' ' ' </proc/$PPID/cmdline 2>/dev/null | cut -c1-60)"
    # This wait mustn't hold the drive either: what it inherited from its
    # launcher (output, log files) may be on it, and a process using the drive
    # can be stopped when the drive goes to the computer. Listed, then let go.
    gz_mine=$(ls -l /proc/$$/fd 2>/dev/null | grep -E -- "-> /mnt/(base-)?us(/|$)" | sed 's/.*-> //' | tr '\n' ' ')
    [ -n "${gz_mine}" ] && gz_usb_log "this wait had open on the drive: ${gz_mine}(let go)"
    gz_drive_users
    eips_print_bottom_centered "Plug the Kindle into the computer (or replug the cable)" 2
    eips_print_bottom_centered "GZreader comes back after you eject it" 1
    exec </dev/null >/dev/null 2>&1
    # (asked to stop by the Kindle: say so in the trace, and keep waiting;
    # only SIGKILL can't be caught: then the trace just ends)
    for gz_sig in HUP INT QUIT TERM USR1 USR2 PIPE ALRM; do
        # shellcheck disable=SC2064
        trap "gz_usb_log 'got SIG${gz_sig}: going on waiting'" ${gz_sig}
    done
    if [ "${GZ_VOLUMD_LATER}" = "yes" ]; then
        # the drive goes to the computer once the framework is up (see above)
        gz_framework_settled
        killall -CONT volumd
        gz_usb_log "the Kindle's USB drive service runs again"
    fi
    GZ_WAITED=0
    while gz_drive_here && gz_latest_wait && [ ${GZ_WAITED} -lt 900 ]; do
        sleep 2
        GZ_WAITED=$((GZ_WAITED + 2))
        [ $((GZ_WAITED % 60)) -eq 0 ] && gz_usb_log "waiting for the USB drive mode (${GZ_WAITED} s)"
    done
    if ! gz_drive_here && gz_latest_wait; then
        gz_usb_log "the drive is shared over USB (after ${GZ_WAITED} s)"
        GZ_GONE=0
        while ! gz_drive_here; do
            sleep 2
            GZ_GONE=$((GZ_GONE + 2))
            # (a heartbeat: where the trace stops is where this wait was stopped)
            [ $((GZ_GONE % 60)) -eq 0 ] && gz_usb_log "the drive is still shared (${GZ_GONE} s)"
        done
        gz_usb_log "the drive is back (after ${GZ_GONE} s)"
        # (the drive settles: fsck, the Kindle's indexer taking in the new
        # books; GZreader stops the framework again when it starts)
        sleep 15
        if gz_latest_wait && [ -f /mnt/us/koreader/koreader.sh ] && ! pidof reader.lua >/dev/null 2>&1; then
            rm -f /var/tmp/gzreader-usbwait
            gz_usb_log "starting GZreader again"
            echo "GZreader: back from USB drive mode at $(date)" >>/mnt/us/koreader/crash.log 2>/dev/null
            rm -f /var/tmp/fbink
            # shellcheck disable=SC2086
            exec /bin/sh /mnt/us/koreader/koreader.sh ${REEXEC_FLAGS}
        fi
        gz_usb_log "not starting GZreader again (another start, or GZreader is gone from the drive)"
    else
        gz_usb_log "no USB drive mode (waited ${GZ_WAITED} s)"
    fi
fi

# Wipe the clones on exit
rm -f /var/tmp/koreader.sh /var/tmp/fbink

exit ${RETURN_VALUE}
