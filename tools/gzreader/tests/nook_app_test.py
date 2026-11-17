#!/usr/bin/env python3
"""GZreader's files on the Nook's card (platform/nook/gzreader.sh, "app parts").

The start script's part between "(begin app parts" and "(end app parts)" is
run under sh on a computer: GZreader's folder and the card are temporary
folders, mounting is played by symbolic links (a bind mount needs root) and
the mount table by a file. Checks: the first start moves the parts that are
only read to the card and mounts them back; the next start only mounts them;
a full package pushed over them is moved again; without the card GZreader
doesn't start; a part that can't be copied stays where it was; GZ_NOOK_APP=here
brings everything back.

    python3 tools/gzreader/tests/nook_app_test.py
"""
import glob
import os
import shutil
import subprocess
import sys
import tempfile

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


def block():
    text = open(os.path.join(REPO, "platform", "nook", "gzreader.sh")).read()
    start = text.index("(begin app parts")
    start = text.index("\n", start) + 1
    end = text.index("# (end app parts)")
    return text[start:end]


STUBS = r'''
log() { echo "$*" >> "$LOG"; }
# (a bind mount needs root: a symbolic link plays it, the mount table a file)
bind_part() { rmdir "$2" && ln -s "$1" "$2" && echo "x $2 vfat rw 0 0" >> "$MOUNTS"; }
unbind_part() {
    [ -L "$1" ] && rm "$1" && mkdir "$1"
    grep -v " $1 " "$MOUNTS" > "$MOUNTS.new"; mv "$MOUNTS.new" "$MOUNTS"
}
cp() {
    case "$*" in *"$GZ_TEST_CP_FAILS"*) [ -n "$GZ_TEST_CP_FAILS" ] && return 1 ;; esac
    command cp "$@"
}
'''


def main():
    work = tempfile.mkdtemp(prefix="gz-app-")
    gz = os.path.join(work, "data", "gzreader")
    ko = os.path.join(gz, "koreader")
    card = os.path.join(work, "card")
    os.makedirs(card)
    parts = {"frontend": "ui.lua", "plugins": "gzreader.koplugin/main.lua", "fonts": "noto/a.ttf",
             "data": "hyph/en.pattern", "ffi": "blitbuffer.lua", "libs": "libluajit.so", "common": "ssl.so",
             "settings": "settings.reader.lua"}
    for d, f in parts.items():
        p = os.path.join(ko, d, f)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        open(p, "w").write(d + "\n")
    open(os.path.join(ko, "data", "ca-bundle.crt"), "w").write("-----BEGIN CERTIFICATE-----\n")
    mounts = os.path.join(work, "mounts")
    open(mounts, "w").write("/dev/block//vold/179:9 %s vfat rw 0 0\n" % card)
    log = os.path.join(work, "log")
    sh = shutil.which("busybox")
    real = os.environ.get("GZ_TEST_BUSYBOX") or sh or next(iter(sorted(glob.glob("/nix/store/*-busybox-*/bin/busybox"))), None)
    shell = [real, "sh"] if real else ["sh"]
    print("shell:", " ".join(shell))
    app = os.path.join(card, ".gzreader-app")

    def start(**env):
        e = dict(os.environ, GZ=gz, GZ_NOOK_HOME=card, MOUNTS=mounts, LOG=log)
        e.update(env)
        script = block() + STUBS + 'app_parts; echo "rc=$? bound=$APP_BOUND nobc=$KO_NO_BYTECODE_CACHE"\n[ -n "$THEN_EXIT" ] && unbind_app\n'
        r = subprocess.run(shell + ["-c", script], env=e, capture_output=True, text=True, timeout=60)
        return r

    def read(*p):
        try:
            return open(os.path.join(*p)).read()
        except OSError:
            return None

    def bound(p):
        return os.path.islink(os.path.join(ko, p))

    try:
        print("GZreader's files on the card")
        r = start()
        check("rc=0" in r.stdout and all(bound(p) for p in ("frontend", "plugins", "fonts", "data", "ffi", "cache")),
              "first start: the parts that are only read (and the cache) mounted from the card (%s%s)" % (r.stdout.strip(), r.stderr.strip()))
        check(read(app, "frontend", "ui.lua") == "frontend\n" and read(ko, "plugins", "gzreader.koplugin", "main.lua") == "plugins\n",
              "…moved there, and GZreader sees them where they were")
        check(not bound("libs") and not bound("common") and not bound("settings")
              and read(ko, "libs", "libluajit.so") == "libs\n" and read(ko, "settings", "settings.reader.lua") == "settings\n",
              "its libraries and settings stay on the Nook's own disk")
        check(read(gz, "app-home").strip() == app and "moving frontend" in read(log), "where they went kept in app-home; logged")
        r = start(THEN_EXIT="1")
        check(not any(bound(p) for p in ("frontend", "plugins")) and os.listdir(os.path.join(ko, "frontend")) == [],
              "on exit: unmounted (empty folders left on the Nook's disk)")
        open(log, "w").close()
        r = start()
        check("rc=0" in r.stdout and bound("frontend") and "moving" not in read(log), "next start: just mounted, nothing copied")
        start(THEN_EXIT="1")
        # GZreader's code on the card: checked before it runs
        manifest = os.path.join(gz, "app-manifest")
        check("plugins/gzreader.koplugin/main.lua" in (read(manifest) or "") and "frontend/ui.lua" in read(manifest)
              and "data/ca-bundle.crt" in read(manifest) and "fonts/" not in read(manifest) and "nobc=1" in r.stdout,
              "its code recorded (SHA-256 of the Lua and data/ca-bundle.crt) on the Nook's own disk; no bytecode cache on the card")
        open(log, "w").close()
        r = start(THEN_EXIT="1")
        check("rc=0" in r.stdout and "as GZreader left it" in read(log), "the next start: the code checked, as GZreader left it")
        def tampered(what, path, text):
            open(log, "w").close()
            keep = read(app, *path)
            os.makedirs(os.path.dirname(os.path.join(app, *path)), exist_ok=True)
            open(os.path.join(app, *path), "w").write(text)
            r = start(THEN_EXIT="1")
            check("rc=1" in r.stdout and "changed by something other than GZreader" in r.stdout and not bound("frontend")
                  and "/".join(path) in read(log), what + ": GZreader doesn't start, says why (%s)" % r.stdout.strip())
            if keep is None:
                os.remove(os.path.join(app, *path))
            else:
                open(os.path.join(app, *path), "w").write(keep)
        tampered("a Lua file on the card changed (by an app, or over USB)", ("frontend", "ui.lua"), "os.execute('evil')\n")
        tampered("a Lua file added to the card", ("plugins", "evil.koplugin", "main.lua"), "os.execute('evil')\n")
        tampered("the certificate authorities changed", ("data", "ca-bundle.crt"), "-----BEGIN CERTIFICATE-----\nevil\n")
        open(os.path.join(app, "fonts", "noto", "b.ttf"), "w").write("font\n")
        r = start(THEN_EXIT="1")
        check("rc=0" in r.stdout, "a font added (not run): starts as usual")
        # an update: GZreader writes the new code itself, and leaves app-manifest.renew
        before = read(manifest)
        open(os.path.join(app, "frontend", "ui.lua"), "w").write("frontend v2\n")
        open(os.path.join(gz, "app-manifest.renew"), "w").write("1.32.0\n")
        r = start(THEN_EXIT="1")
        check("rc=0" in r.stdout and not os.path.exists(os.path.join(gz, "app-manifest.renew"))
              and read(manifest) != before and start(THEN_EXIT="1").stdout.count("rc=0") == 1,
              "after an update (app-manifest.renew): its code recorded again, and checked from then on")
        # a full package pushed over GZreader with adb
        os.remove(os.path.join(ko, "frontend")) if os.path.islink(os.path.join(ko, "frontend")) else None
        open(os.path.join(ko, "frontend", "new.lua"), "w").write("new\n")
        r = start()
        check(bound("frontend") and read(ko, "frontend", "new.lua") == "new\n" and read(ko, "frontend", "ui.lua") is None,
              "a full package pushed over it: moved to the card again, replacing the old copy")
        # leftover mounts from a GZreader that didn't close properly
        r = start()
        check("rc=0" in r.stdout and bound("frontend") and read(ko, "frontend", "new.lua") == "new\n",
              "started again while still mounted (a GZreader that didn't close): unmounted first, mounted again")
        start(THEN_EXIT="1")
        # the card taken out
        os.rename(app, app + ".away")
        r = start()
        check("rc=1" in r.stdout and "put that card back" in r.stdout and not bound("frontend"),
              "the card taken out: GZreader doesn't start, says why")
        os.rename(app + ".away", app)
        # a part that can't be copied (the card full)
        open(os.path.join(ko, "fonts", "big.ttf"), "w").write("big\n") if not bound("fonts") else None
        r = start(GZ_TEST_CP_FAILS="fonts")
        check("rc=0" in r.stdout and not bound("fonts") and read(ko, "fonts", "big.ttf") == "big\n" and bound("frontend")
              and "couldn't copy fonts" in read(log),
              "a part that can't be copied: stays on the Nook's disk (the others on the card)")
        start(THEN_EXIT="1")
        # all back on the Nook's disk
        r = start(GZ_NOOK_APP="here")
        check("rc=0" in r.stdout and not any(bound(p) for p in ("frontend", "plugins", "fonts"))
              and read(ko, "frontend", "new.lua") == "new\n" and read(ko, "plugins", "gzreader.koplugin", "main.lua") == "plugins\n"
              and read(gz, "app-home") is None and not os.path.exists(os.path.join(app, "frontend")),
              "GZ_NOOK_APP=here: everything brought back to the Nook's disk, nothing left on the card")
        r = start(GZ_NOOK_APP="here")
        check("rc=0" in r.stdout and not bound("frontend"), "…and kept there")
    finally:
        shutil.rmtree(work, ignore_errors=True)
    print("%d passed, %d failed" % (passed, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
