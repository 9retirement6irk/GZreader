#!/usr/bin/env python3
"""GZreader's changes to KOReader's and ZenOS's own files, counted.

GZreader marks what it changes in upstream files (comments and code saying
GZreader, Grimmory, gzreader, _gz…). keeps.txt records, for each such file,
how many marks it has; this check fails when a file has fewer (or is gone),
which is what an upstream merge that quietly dropped a GZreader change looks
like. It also checks the files and words GZreader's names depend on.

  keeps.py           check (exit 1 on a loss)
  keeps.py --update  record the current counts (after changing them on purpose)
"""
import os, re, sys

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
MANIFEST = os.path.join(os.path.dirname(__file__), "keeps.txt")
# upstream-owned places (GZreader's own plugin and tools aren't touched by merges)
ROOTS = ["frontend", "reader.lua", "platform/kindle", "plugins/zenos.koplugin",
         "plugins/coverbrowser.koplugin", "plugins/statistics.koplugin", "plugins/autosuspend.koplugin"]
MARK = re.compile(r"GZreader|Grimmory|gzreader|_gz_|\bgz_|\bGz[A-Z]|gz-")
# names and pieces that must exist, whatever the counts say
MUST = [
    ("platform/kindle/extensions/koreader/menu.json", "GZreader"),
    ("platform/kindle/extensions/koreader/config.xml", "GZreader"),
    ("platform/kindle/launchpad/koreader.ini", "GZreader"),
    ("plugins/zenos.koplugin/kindle-launcher/GZreader.sh", "GZreader"),
    ("plugins/zenos.koplugin/icons/quick_read_aloud.svg", "<svg"),
    ("plugins/zenos.koplugin/icons/tab_calendar.svg", "<svg"),
    ("plugins/zenos.koplugin/modules/settings/zen_settings.lua", "Connections"),
    ("plugins/zenos.koplugin/modules/menu/patches/quick_settings.lua", "read_aloud"),
    ("plugins/zenos.koplugin/modules/filebrowser/patches/navbar.lua", "onGzOptions"),
    ("plugins/zenos.koplugin/common/quickstart/quickstart_pages.lua", "Set up from your browser"),
    ("frontend/ui/elements/filemanager_menu_order.lua", "gzreader"),
    ("frontend/ui/elements/reader_menu_order.lua", "gzreader"),
    ("frontend/device.lua", "device/nook/device"),
    ("plugins/gzreader.koplugin/gzreader_picturebook.lua", "GZreader picture book"),
    ("plugins/zenos.koplugin/modules/menu/patches/app_launcher.lua", "gz_context"),
    ("plugins/zenos.koplugin/common/ui/icon_menu_item.lua", "items_per_page_default"),
    ("frontend/device/kindle/device.lua", "physicalSize"),
    ("plugins/zenos.koplugin/modules/settings/zen_settings.lua", "copyItems"),
    ("plugins/zenos.koplugin/common/quickstart/quickstart_pages.lua", "GzCopyReceive"),
    ("plugins/zenos.koplugin/config/defaults.lua", "ct_music"),
    ("plugins/zenos.koplugin/config/manager.lua", "gz_music_tab_migrated"),
    ("plugins/zenos.koplugin/icons/tab_music.svg", "<svg"),
]


def files():
    for root in ROOTS:
        p = os.path.join(REPO, root)
        if os.path.isfile(p):
            yield root
            continue
        for d, _dirs, fs in os.walk(p):
            for f in fs:
                if f.endswith((".lua", ".sh", ".json", ".xml", ".ini")):
                    yield os.path.relpath(os.path.join(d, f), REPO)


def count(rel):
    try:
        with open(os.path.join(REPO, rel), encoding="utf-8", errors="replace") as f:
            return len(MARK.findall(f.read()))
    except FileNotFoundError:
        return None


def main():
    if "--update" in sys.argv:
        rows = sorted((rel, n) for rel in files() for n in [count(rel)] if n)
        with open(MANIFEST, "w") as f:
            f.write("# GZreader's marks in upstream files (tools/gzreader/tests/keeps.py --update)\n")
            for rel, n in rows:
                f.write(f"{n} {rel}\n")
        print(f"recorded {len(rows)} files")
        return 0
    lost = []
    with open(MANIFEST) as f:
        for line in f:
            if line.startswith("#") or not line.strip():
                continue
            n, rel = line.rstrip("\n").split(" ", 1)
            now = count(rel)
            if now is None:
                lost.append(f"{rel}: gone (had {n} GZreader changes)")
            elif now < int(n):
                lost.append(f"{rel}: {now} GZreader marks, was {n}")
    for rel, word in MUST:
        p = os.path.join(REPO, rel)
        if not os.path.exists(p) or word not in open(p, encoding="utf-8", errors="replace").read():
            lost.append(f"{rel}: should have \"{word}\"")
    for l in lost:
        print("  FAIL " + l)
    print(f"{'kept' if not lost else 'LOST'}: GZreader's changes to upstream files ({len(lost)} problems)")
    return 1 if lost else 0


sys.exit(main())
