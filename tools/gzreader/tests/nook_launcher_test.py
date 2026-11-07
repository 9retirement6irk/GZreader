#!/usr/bin/env python3
"""GZreader's Nook launcher helper (platform/nook/launcher.sh) on a computer.

The Nook's BusyBox is played by a small script that runs the command it's
given (and bash for "sh"); the Nook's start-up script is a temporary file;
gzreader.sh is a stand-in that notes each start. Checks: install adds the
start-up line once and starts the helper; "start" in the pipe starts
GZreader once, also when tapped twice; anything else is ignored; uninstall
takes the line out and stops the helper.

    python3 tools/gzreader/tests/nook_launcher_test.py
"""
import glob
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import time

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
passed = failed = 0


def check(cond, msg):
    global passed, failed
    if cond:
        passed += 1
        print("  ok  ", msg)
    else:
        failed += 1
        print("  FAIL", msg)


def wait_for(cond, seconds=8.0):
    end = time.time() + seconds
    while time.time() < end:
        if cond():
            return True
        time.sleep(0.1)
    return cond()


def _eof(fd):
    try:
        return os.read(fd, 100) == b""
    except BlockingIOError:
        return False


def main():
    work = tempfile.mkdtemp(prefix="gz-launcher-")
    gz = os.path.join(work, "gzreader")
    os.makedirs(os.path.join(gz, "runtime"))
    shutil.copy(os.path.join(REPO, "platform", "nook", "launcher.sh"), os.path.join(gz, "launcher.sh"))
    bb = os.path.join(gz, "runtime", "busybox")
    real = os.environ.get("GZ_TEST_BUSYBOX") or shutil.which("busybox") or next(iter(sorted(
        glob.glob("/nix/store/*-busybox-*/bin/busybox"))), None)
    with open(bb, "w") as f:
        if real:
            # a real BusyBox's shell (ash: read -t, exec 3<>, as on the Nook); no remounting here
            # (its shell; the other commands: this computer's; root, as on the Nook (CI runs as a user))
            f.write('#!/bin/sh\ncase "$1" in sh) exec %s "$@" ;; mount) exit 1 ;; id) echo 0; exit 0 ;; umount) echo "$2" >> "$GZ/umounts"; exit 0 ;; pidof) [ -f "$GZ/running" ] && echo 123 && exit 0; exit 1 ;; esac\nexec "$@"\n' % real)
        else:
            f.write('#!/bin/bash\n# the Nook\'s BusyBox, played by this computer\'s commands\n'
                    'case "$1" in sh) shift; exec bash "$@" ;; mount) exit 1 ;; id) echo 0; exit 0 ;; umount) echo "$2" >> "$GZ/umounts"; exit 0 ;; pidof) [ -f "$GZ/running" ] && echo 123 && exit 0; exit 1 ;; esac\nexec "$@"\n')
    print("BusyBox:", real or "none here (bash and this computer's commands)")
    os.chmod(bb, 0o755)
    starts = os.path.join(work, "starts")
    with open(os.path.join(gz, "gzreader.sh"), "w") as f:
        # (GZreader for 2 s; the helper waits for it)
        f.write('echo "start $GZ_IN_BUSYBOX" >> %s\nsleep 2\n' % starts)
    hook = os.path.join(work, "bravo_pltinfo.sh")
    original = "#!/system/bin/sh\n\n# Populate Bravo platform info\n/system/bin/pltinfo ModelNumber >/dev/null\n"
    with open(hook, "w") as f:
        f.write(original)
    env = dict(os.environ, GZ=gz, GZ_NOOK_BOOT_SCRIPT=hook, GZ_IN_BUSYBOX="")
    env.pop("GZ_IN_BUSYBOX")

    def launcher(*args):
        return subprocess.run(["bash", os.path.join(gz, "launcher.sh")] + list(args), env=env,
                              capture_output=True, text=True, timeout=30)

    def helper_pid():
        try:
            return int(open(os.path.join(gz, "launch", "helper.pid")).read().strip())
        except (OSError, ValueError):
            return None

    def alive(pid):
        if not pid:
            return False
        try:
            os.kill(pid, 0)
        except OSError:
            return False
        # (a finished helper may linger as a zombie of this test)
        try:
            return open("/proc/%d/stat" % pid).read().split()[2] != "Z"
        except OSError:
            return False

    def tap(word="start"):
        fd = os.open(os.path.join(gz, "launch", "start"), os.O_WRONLY | os.O_NONBLOCK)
        os.write(fd, (word + "\n").encode())
        os.close(fd)

    def count_starts():
        try:
            return len(open(starts).read().splitlines())
        except OSError:
            return 0

    try:
        print("Nook launcher helper")
        # (adb's shell hands its children its connection on more descriptors:
        # adb waits until every copy is closed)
        conn_r, conn_w = os.pipe()
        extra = [os.dup(conn_w) for _ in range(3)]
        p = subprocess.Popen(["bash", os.path.join(gz, "launcher.sh"), "install"], env=env, pass_fds=[conn_w] + extra,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        out, err = p.communicate(timeout=30)
        for fd in [conn_w] + extra:
            os.close(fd)
        check(p.returncode == 0 and "Tap GZreader" in out, "install: done, says how to start it (%s%s)" % (out.strip(), err.strip()))
        os.set_blocking(conn_r, False)
        closed = wait_for(lambda: _eof(conn_r), 5)
        os.close(conn_r)
        check(closed, "…and returns for good: the helper keeps none of the connection it was started from open")
        text = open(hook).read()
        check(text.startswith(original) and text.count("# GZreader launcher helper") == 1
              and ("[ -f %s/launcher.sh ] && /system/bin/sh %s/launcher.sh start" % (gz, gz)) in text,
              "the Nook's start-up script: its own lines kept, ours added (start the helper if GZreader is there)")
        pipe = os.path.join(gz, "launch", "start")
        check(os.path.exists(pipe) and stat.S_ISFIFO(os.stat(pipe).st_mode) and stat.S_IMODE(os.stat(pipe).st_mode) == 0o622,
              "the pipe the icon writes to: there, writable by an app")
        check(stat.S_IMODE(os.stat(gz).st_mode) & 0o001 and stat.S_IMODE(os.stat(os.path.join(gz, "launch")).st_mode) & 0o001,
              "…and the folders on the way to it open to apps")
        pid = helper_pid()
        check(alive(pid), "the helper runs")
        time.sleep(1)
        st = open("/proc/%d/stat" % pid).read().split()[2] if pid else "?"
        check(st == "S", "…waiting, not spinning (state %s)" % st)
        r = launcher("install")
        check(r.returncode == 0 and open(hook).read().count("# GZreader launcher helper") == 1 and helper_pid() == pid,
              "install again: nothing added twice, the same helper")
        r = launcher("start")
        check(r.returncode == 0 and helper_pid() == pid and "the helper runs already" in open(os.path.join(gz, "launch", "helper.log")).read(),
              "start (the Nook's start-up) with the helper running: the same helper, logged")

        tap("hello")
        time.sleep(0.5)
        check(count_starts() == 0, "anything but start: ignored")
        tap()
        check(wait_for(lambda: count_starts() == 1), "start: GZreader started")
        check(open(starts).read().split()[1:] == [], "…through BusyBox's sh again (the start script re-runs itself in BusyBox)")
        time.sleep(0.3)
        tap()
        tap()
        time.sleep(3.5)
        check(count_starts() == 1, "taps while GZreader runs: no second GZreader, also not after it closes (%d)" % count_starts())
        tap()
        check(wait_for(lambda: count_starts() == 2), "a tap after it closed: started again")
        time.sleep(2.5)
        log = open(os.path.join(gz, "launch", "helper.log")).read()
        check("helper waiting" in log and log.count("starting GZreader") == 2 and "GZreader closed" in log, "the helper's log says what it did")

        r = launcher("uninstall")
        check(r.returncode == 0 and open(hook).read() == original + "\n", "uninstall: our lines out, the Nook's own as they were")
        check(wait_for(lambda: not alive(pid), 3) and not os.path.exists(pipe), "…the helper stopped, the pipe gone")
        # GZreader's own /system/etc mounted over the Nook's (while it runs, or left over)
        mounts = os.path.join(work, "mounts")
        with open(mounts, "w") as f:
            f.write("/dev/block/mtdblock4 /system yaffs2 ro 0 0\n/data/gzreader/run/etc /system/etc yaffs2 rw 0 0\n")
        env["GZ_MOUNTS"] = mounts
        open(os.path.join(gz, "running"), "w").close()
        r = launcher("install")
        check(r.returncode == 1 and "Exit to Nook" in r.stdout and "# GZreader" not in open(hook).read(),
              "install while GZreader runs (its /system/etc over the Nook's): asks to exit it first, changes nothing")
        os.remove(os.path.join(gz, "running"))
        r = launcher("install")
        check(r.returncode == 0 and open(os.path.join(gz, "umounts")).read().strip() == "/system/etc"
              and open(hook).read().count("# GZreader launcher helper") == 1,
              "…left over from a GZreader that didn't close: unmounted, then installed")
        launcher("uninstall")
        env.pop("GZ_MOUNTS")
        # after a restart: the old pid file names a process that isn't the helper
        stale = subprocess.Popen(["sleep", "30"])
        os.makedirs(os.path.join(gz, "launch"), exist_ok=True)
        with open(os.path.join(gz, "launch", "helper.pid"), "w") as f:
            f.write(str(stale.pid))
        r = launcher("start")
        newpid = helper_pid()
        check(r.returncode == 0 and newpid and newpid != stale.pid and alive(newpid)
              and "start: helper started" in open(os.path.join(gz, "launch", "helper.log")).read(),
              "start after a restart, the old pid now someone else's: the helper started")
        stale.kill()
        launcher("uninstall")
        r = launcher("frobnicate")
        check(r.returncode == 1 and "Usage" in r.stdout, "anything else: usage")
    finally:
        pid = helper_pid()
        if alive(pid):
            os.kill(pid, 15)
        shutil.rmtree(work, ignore_errors=True)
    print("%d passed, %d failed" % (passed, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
