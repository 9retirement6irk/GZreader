#!/usr/bin/env python3
"""The Kindle start script's "Sync with computer" step-aside (exit 86), run
for real under sh with a pretend clock, drive (/proc/mounts) and framework.

    python3 kindle_usb_test.py

What it checks (platform/kindle/koreader.sh):
- Kindle 2/3/DX (sysv): the framework starts first; the Kindle's USB service
  (volumd) stays paused until the framework has booted (its Java VM, cvm,
  calm), so the drive never goes to the computer while it's starting; then
  GZreader starts again once the drive is back.
- Firmware 5 (upstart): the Kindle interface comes back first, as before.
- Every stage goes to /var/local/gzreader-usb.log, which the next start
  folds into crash.log.
"""
import os
import re
import subprocess
import sys
import tempfile

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
SCRIPT = open(os.path.join(REPO, "platform", "kindle", "koreader.sh")).read()
failed = 0


def check(cond, what):
    global failed
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        failed += 1


def localize(text, fake):
    for real, pretend in [("/var/tmp/", fake + "/tmp/"), ("/var/local/", fake + "/local/"),
                          ("/proc/mounts", fake + "/mounts"), ("/etc/init.d/framework", fake + "/framework"),
                          ("/mnt/us/koreader/", fake + "/us/koreader/"),
                          ("-> /mnt/(base-)?us(/|$)", "-> " + fake + "/us(/|$)"),
                          ("/proc/${gz_cvm}/stat", fake + "/cvmstat"), ("/proc/keypad", fake + "/keypad"),
                          ("/proc/sys/kernel/random/boot_id", fake + "/boot_id")]:
        text = text.replace(real, pretend)
    return text


STEP_ASIDE = SCRIPT[SCRIPT.index("# GZreader: stepping aside for the USB drive (exit 86) with the framework"):]
FOLD = SCRIPT[SCRIPT.index("# GZreader: what the last \"Sync with computer\""):SCRIPT.index("# we keep at most 500KB")]


def rc_open_after(fake):
    """How many files the wait had open on the pretend drive while it waited."""
    return int(open(fake + "/held").read().strip() or "0") if os.path.exists(fake + "/held") else -1


def run(world, init_type="sysv", stop_framework="yes", hold_drive=False, fw_busy=60, cvm=True):
    """world: shell lines deciding the drive from $t (seconds so far); `gone`
    only works once volumd runs (it's what shares the drive). The framework's
    cvm uses 0.8 s of CPU a second for fw_busy seconds after it starts."""
    fake = tempfile.mkdtemp()
    for d in ("tmp", "local", "us/koreader"):
        os.makedirs(os.path.join(fake, d))
    ev = fake + "/events"
    open(fake + "/clock", "w").write("0")
    open(fake + "/boot_id", "w").write("11111111-aaaa\n")
    open(fake + "/mounts", "w").write("/dev/loop/0 /mnt/us vfat rw 0 0\n")
    with open(fake + "/framework", "w") as f:
        f.write('#!/bin/sh\necho "FRAMEWORK $1 t=$(cat %s/clock)" >> %s\n' % (fake, ev)
                + ('cat %s/clock > %s/cvm_up\n' % (fake, fake) if cvm else ""))
    with open(fake + "/us/koreader/koreader.sh", "w") as f:
        f.write('echo "RELAUNCH $* t=$(cat %s/clock)" >> %s\n' % (fake, ev))
    with open(fake + "/world", "w") as f:
        f.write("#!/bin/sh\nt=$1\nhere() { echo '/dev/loop/0 /mnt/us vfat rw 0 0' > %s/mounts; }\n"
                "gone() { [ -f %s/volumd_at ] && : > %s/mounts; }\n"
                # (the framework's cvm: busy for a while after it starts, then calm)
                "if [ -f %s/cvm_up ]; then u=$(( t - $(cat %s/cvm_up) )); [ $u -gt %d ] && u=%d; echo \"4242 (cvm) S 1 1 1 0 0 0 0 0 0 0 $((u * 80)) 0 0\" > %s/cvmstat; fi\n"
                # (while it waits: what the wait, our parent, has open on the drive)
                "[ $t -eq 20 ] && ls -l /proc/$PPID/fd 2>/dev/null | grep -c -- '-> %s/us/' > %s/held\n%s\n"
                % (fake, fake, fake, fake, fake, fw_busy, fw_busy, fake, fake, fake, world))
    for p in ("framework", "world"):
        os.chmod(os.path.join(fake, p), 0o755)
    prelude = """
INIT_TYPE={init}; STOP_FRAMEWORK={stop}; RETURN_VALUE=86; VOLUMD_STOPPED=yes
KOREADER_DIR={fake}/us/koreader; REEXEC_FLAGS=" --framework_stop"; PASSCODE_DISABLED=no
logmsg() {{ :; }}
eips_print_bottom_centered() {{ echo "SCREEN $1" >> {ev}; }}
pidof() {{ [ "$1" = cvm ] && [ -f {fake}/cvm_up ] && echo 4242 && return 0; return 1; }}
killall() {{ echo "KILLALL $* t=$(cat {fake}/clock)" >> {ev}; [ "$*" = "-CONT volumd" ] && cat {fake}/clock > {fake}/volumd_at; return 0; }}
iptables() {{ :; }}
start() {{ echo "FRAMEWORK upstart-$1 t=$(cat {fake}/clock)" >> {ev}; cat {fake}/clock > {fake}/cvm_up; }}
sleep() {{ n=$(( $(cat {fake}/clock) + $1 )); echo $n > {fake}/clock; {fake}/world $n; }}
""".format(init=init_type, stop=stop_framework, fake=fake, ev=ev)
    path = fake + "/step.sh"
    open(path, "w").write(prelude + localize(STEP_ASIDE, fake))
    if hold_drive:
        with open(fake + "/us/launcher-output.txt", "w") as out:
            rc = subprocess.run(["sh", path], cwd=fake, timeout=60, stdout=out, stderr=out).returncode
    else:
        rc = subprocess.run(["sh", path], cwd=fake, timeout=60, stdout=subprocess.DEVNULL).returncode
    events = open(ev).read() if os.path.exists(ev) else ""
    trace = open(fake + "/local/gzreader-usb.log").read() if os.path.exists(fake + "/local/gzreader-usb.log") else ""
    return rc, events, trace, fake


print("Kindle start script: stepping aside for the USB drive")


def at(ev, what):
    m = re.search(re.escape(what) + r" t=(\d+)", ev)
    return int(m.group(1)) if m else None


# 1. the usual sync (cable in already): framework first, the drive only once it has booted
rc, ev, trace, fake = run('[ $t -ge 10 ] && gone; [ $t -ge 140 ] && here; :')
check(at(ev, "FRAMEWORK start") == 0 and ev.count("FRAMEWORK") == 1,
      "Kindle 2/3/DX: the framework starts first (it hands the drive to the computer on firmware 2.x)")
check(at(ev, "KILLALL -CONT volumd") == 70 and "the Kindle interface is up (after 70 s; cvm CPU per 5 s, 1/100 s: ? 400" in trace,
      "the USB drive service stays paused until the framework has booted (its cvm calm), then runs again")
check(0 <= trace.find("the Kindle's USB drive service runs again") < trace.find("the drive is shared over USB"),
      "…so the drive goes to the computer only after that")
check("RELAUNCH --framework_stop t=" in ev and at(ev, "RELAUNCH --framework_stop") >= 140 + 15,
      "GZreader starts again once the drive is back (same flags), after 15 s to settle")
check("the drive is still shared (60 s)" in trace and "the drive is back" in trace and "starting GZreader again" in trace,
      "each stage in /var/local/gzreader-usb.log, with a heartbeat every minute while shared")
check(not os.path.exists(fake + "/tmp/gzreader-usbwait"), "the wait marker is removed")

check("boot 11111111-aaaa, up " in trace and re.search(r"wait \d+ \(group \d+\), started by \d+", trace),
      "the trace says which boot this is and who the wait belongs to")

# 1b. a framework calm from the start still gets 45 s (a DX's took 20 s: too early)
rc, ev, trace, fake = run('gone; [ $t -ge 200 ] && here; :', fw_busy=0)
check(at(ev, "KILLALL -CONT volumd") == 50, "cvm calm at once: the drive is shared only once it has been there 45 s")

# 1c. asked to stop while the drive is shared: logged, and it goes on
rc, ev, trace, fake = run('gone; [ $t -eq 100 ] && kill -TERM $PPID; [ $t -ge 140 ] && here; :')
check("got SIGTERM: going on waiting" in trace and "RELAUNCH" in ev, "a TERM while waiting is in the trace, and GZreader still comes back")

# 2. a framework that never calms down, or no cvm at all: on after 4 minutes
rc, ev, trace, fake = run('gone; [ $t -ge 300 ] && here; :', fw_busy=10000)
check(at(ev, "KILLALL -CONT volumd") == 240 and "still busy after 240 s: going on" in trace and "RELAUNCH" in ev,
      "framework still busy: the drive is shared after 4 minutes anyway, GZreader comes back")
rc, ev, trace, fake = run('gone; [ $t -ge 300 ] && here; :', cvm=False)
check(at(ev, "KILLALL -CONT volumd") == 240 and "RELAUNCH" in ev, "no cvm to watch: the same")

# 3. plugged in late: a heartbeat while waiting for the USB drive mode
rc, ev, trace, fake = run('[ $t -ge 200 ] && gone; [ $t -ge 230 ] && here; :')
check("waiting for the USB drive mode (60 s)" in trace and "waiting for the USB drive mode (120 s)" in trace
      and "RELAUNCH" in ev and ev.count("FRAMEWORK") == 1, "plugged in after 2 minutes: heartbeats, then GZreader comes back")

# 4. never plugged in: 15 minutes, then the Kindle stays on its own interface
rc, ev, trace, fake = run(':')
check(ev.count("FRAMEWORK") == 1 and "RELAUNCH" not in ev and "no USB drive mode (waited 900 s)" in trace,
      "never plugged in: 15 minutes, GZreader not started (the framework already runs)")

# 5. GZreader gone from the drive (deleted on the computer)
rc, ev, trace, fake = run('gone; [ $t -ge 100 ] && { here; rm -f %s; }; :' % "$(dirname $0)/us/koreader/koreader.sh")
check("RELAUNCH" not in ev and "not starting GZreader again" in trace, "GZreader gone from the drive: not started again")

# 6. firmware 5 (upstart): the Kindle interface first and the drive service at once, as before
rc, ev, trace, fake = run('gone; [ $t -ge 30 ] && here; :', init_type="upstart")
check(at(ev, "KILLALL -CONT volumd") == 0 and at(ev, "FRAMEWORK upstart-lab126_gui") == 0 and "RELAUNCH" in ev,
      "firmware 5: volumd and lab126_gui right away, then the wait")

# 7. framework kept running (cvm paused): nothing to start, volumd at once
rc, ev, trace, fake = run('gone; [ $t -ge 30 ] && here; :', stop_framework="no")
check("FRAMEWORK" not in ev and at(ev, "KILLALL -CONT volumd") == 0 and "RELAUNCH" in ev,
      "framework not stopped: nothing to start, volumd at once")

# 8. the wait doesn't hold the drive: what it inherited (here: its output,
#    on the pretend drive) is listed and let go; asked to stop, it goes on
rc, ev, trace, fake = run('[ $t -ge 10 ] && gone; [ $t -ge 100 ] && here; :', hold_drive=True)
check("this wait had open on the drive:" in trace and "(let go)" in trace, "the wait's own files on the drive are listed and let go")
check(rc_open_after(fake) == 0, "…none still open while it waits")
check("for gz_sig in HUP INT QUIT TERM" in STEP_ASIDE, "…and catches the signals that can be caught")

# 9. a GZreader leftover holding the drive is stopped
check("gz_drive_users" in STEP_ASIDE and "kill \"${gz_pid}\"" in STEP_ASIDE and "-> /mnt/us/koreader/" in STEP_ASIDE,
      "leftovers holding files in GZreader's folder are stopped before the wait")
check(re.search(r'RETURN_VALUE}" -eq 86 \]; then\s+sync\s+fi', SCRIPT), "what GZreader wrote is flushed to the drive before it's shared")

# 10. the next start puts the trace in crash.log, says whether the Kindle restarted, and removes it
for same in (True, False):
    fake = tempfile.mkdtemp()
    os.makedirs(fake + "/local")
    open(fake + "/boot_id", "w").write("11111111-aaaa\n" if same else "22222222-bbbb\n")
    open(fake + "/local/gzreader-usb.log", "w").write("2026-11-06 22:26:03 stepping aside\n"
        "2026-11-06 22:26:03 boot 11111111-aaaa, up 812.5 s; wait 9 (group 9), started by 1: sh\n2026-11-06 22:26:13 the drive is shared\n")
    open(fake + "/crash.log", "w").write("before\n")
    subprocess.run(["sh", "-c", localize(FOLD, fake)], cwd=fake, check=True)
    crash = open(fake + "/crash.log").read()
    if same:
        check("===== last USB drive step-aside =====" in crash and "the drive is shared" in crash and crash.startswith("before\n")
              and "(the Kindle hasn't restarted since" in crash and not os.path.exists(fake + "/local/gzreader-usb.log"),
              "next start: the trace goes into crash.log, the Kindle didn't restart")
    else:
        check("(the Kindle restarted since" in crash, "…and when it did, the trace says so (another boot id)")

print("%d failed" % failed if failed else "all passed")
sys.exit(1 if failed else 0)
