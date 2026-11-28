#!/usr/bin/env python3
"""The package leaves out ZenOS files GZreader never loads (package-common.sh's
GZ_UNUSED_ZENOS, removed by gz_trim). They stay in the repo as upstream has
them. This fails if a listed file is missing from the repo (an upstream merge
renamed it), isn't removed from a packaged tree, or if anything in the plugins
or the frontend starts to load one.

  python3 package_trim_test.py
"""
import os, re, subprocess, sys, tempfile

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
COMMON = os.path.join(REPO, "tools", "gzreader", "package-common.sh")
ZENOS = os.path.join(REPO, "plugins", "zenos.koplugin")
passed = failed = 0


def check(ok, what):
    global passed, failed
    if ok:
        passed += 1
        print("  ok   " + what)
    else:
        failed += 1
        print("  FAIL " + what)


out = subprocess.run(["bash", "-c", '. "$0"; echo "$GZ_UNUSED_ZENOS"', COMMON], capture_output=True, text=True)
unused = out.stdout.split()
check(len(unused) == 4, "four files are left out (%d)" % len(unused))
check(all(os.path.isfile(os.path.join(ZENOS, f)) for f in unused), "each is still in the repo, as upstream has it")

# nothing loads them: no require of the module path anywhere GZreader ships Lua
sources = []
for root in ("plugins", "frontend"):
    for d, _dirs, files in os.walk(os.path.join(REPO, root)):
        for name in files:
            if name.endswith(".lua"):
                sources.append(os.path.join(d, name))
loaded_by = {}
for f in unused:
    module = f[:-4]
    pat = re.compile(r"""["']%s["']""" % re.escape(module))
    for path in sources:
        if os.path.join(ZENOS, f) == path:
            continue
        with open(path, encoding="utf-8", errors="replace") as fh:
            if pat.search(fh.read()):
                loaded_by.setdefault(f, []).append(os.path.relpath(path, REPO))
check(not loaded_by, "nothing in the plugins or the frontend loads one of them %s" % (loaded_by or ""))

# gz_trim removes them from a packaged tree, and nothing beside them
with tempfile.TemporaryDirectory() as tmp:
    ko = os.path.join(tmp, "koreader")
    for f in unused + ["modules/settings/gz_updater.lua", "modules/global/patches/menu_font.lua"]:
        p = os.path.join(ko, "plugins", "zenos.koplugin", f)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        open(p, "w").close()
    os.makedirs(os.path.join(ko, "l10n"))
    os.makedirs(os.path.join(ko, "fonts", "noto"))
    r = subprocess.run(["bash", "-c", 'set -e; . "$0"; gz_trim "$1"', COMMON, ko], capture_output=True, text=True)
    left = [f for f in unused if os.path.exists(os.path.join(ko, "plugins", "zenos.koplugin", f))]
    check(r.returncode == 0 and not left, "gz_trim takes them out of the package %s %s" % (left or "", r.stderr.strip()))
    check(os.path.exists(os.path.join(ko, "plugins/zenos.koplugin/modules/settings/gz_updater.lua"))
          and os.path.exists(os.path.join(ko, "plugins/zenos.koplugin/modules/global/patches/menu_font.lua")),
          "…and leaves the files beside them")

print("package trim: %d passed, %d failed" % (passed, failed))
sys.exit(1 if failed else 0)
