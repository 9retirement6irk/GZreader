#!/usr/bin/env python3
"""The wiki (wiki/, published by .github/workflows/gzreader-wiki.yml): every
link to another page goes to a page that exists, every #anchor to a heading
on it, every page is in the sidebar, and no page points at GZREADER.md's
own anchors (which don't exist in the wiki), and the KOReader and ZenOS
versions the pages (and README and the landing page) name are the ones in
tools/gzreader/UPSTREAM: an upstream merge has to update them."""
import os
import re
import sys

WIKI = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "wiki")
passed = failed = 0


def check(cond, msg):
    global passed, failed
    passed, failed = (passed + 1, failed) if cond else (passed, failed + 1)
    print("  ok  " if cond else "  FAIL", msg)


def slug(t):
    t = re.sub(r"[^\w\- ]", "", t.strip().lower(), flags=re.U)
    return t.replace(" ", "-")


def main():
    pages = {f[:-3]: open(os.path.join(WIKI, f), encoding="utf-8").read()
             for f in os.listdir(WIKI) if f.endswith(".md")}
    anchors = {p: {slug(h) for h in re.findall(r"(?m)^#{1,6} (.+)$", t)} for p, t in pages.items()}
    bad, bad_anchor, stale = [], [], []
    for p, text in pages.items():
        for target in re.findall(r"\]\(([^)\s]+)\)", text):
            if re.match(r"^(https?:|mailto:)", target):
                continue
            page, _, anchor = target.partition("#")
            page = page or p
            if page not in pages:
                bad.append("%s → %s" % (p, target))
            elif anchor and anchor not in anchors[page]:
                bad_anchor.append("%s → %s" % (p, target))
            if "GZREADER.md" in target:
                stale.append("%s → %s" % (p, target))
    print("Wiki")
    check("Home" in pages and "_Sidebar" in pages, "a Home page and a sidebar")
    check(not bad, "links go to pages that exist " + "; ".join(bad[:5]))
    check(not bad_anchor, "#anchors go to headings on that page " + "; ".join(bad_anchor[:5]))
    check(not stale, "no links into GZREADER.md " + "; ".join(stale))
    sidebar = set(re.findall(r"\]\(([^)#\s]+)", pages.get("_Sidebar", "")))
    missing = sorted(set(pages) - sidebar - {"Home", "_Sidebar", "_Footer"})
    check(not missing, "every page is in the sidebar " + ", ".join(missing))
    # the versions the pages name match what GZreader is built on
    upstream = dict(l.split()[:2] for l in open(os.path.join(WIKI, "..", "tools", "gzreader", "UPSTREAM"))
                    if l.strip() and not l.startswith("#"))
    # (the wiki, README and the landing page: the places an upstream merge must update)
    root = os.path.join(WIKI, "..")
    texts = dict(pages)
    for f in ("README.md", os.path.join("docs", "index.html")):
        texts[f] = open(os.path.join(root, f), encoding="utf-8").read()
    named, wrong = 0, []
    for p, text in texts.items():
        found = re.findall(r"\b(KOReader|ZenOS)\b[^`\n<]{0,80}?(?:`|<code>)(v?\d+\.\d+(?:\.\d+)?)(?:`|</code>)", text)
        found += [("KOReader", v) for v in re.findall(r"koreader-kindle[a-z0-9-]*-(v\d+\.\d+\.\d+)\.zip", text)]
        for name, ver in found:
            named += 1
            if ver.lstrip("v") != upstream[name.lower()].lstrip("v"):
                wrong.append("%s: %s %s (UPSTREAM: %s)" % (p, name, ver, upstream[name.lower()]))
    check(named >= 3 and not wrong,
          "KOReader/ZenOS versions in the wiki, README and landing page match tools/gzreader/UPSTREAM "
          + "; ".join(wrong))
    print("%d passed, %d failed" % (passed, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
