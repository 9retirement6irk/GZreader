#!/usr/bin/env python3
"""The wiki (wiki/, published by .github/workflows/gzreader-wiki.yml): every
link to another page goes to a page that exists, every #anchor to a heading
on it, every page is in the sidebar, and no page points at GZREADER.md's
own anchors (which don't exist in the wiki)."""
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
    print("%d passed, %d failed" % (passed, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
