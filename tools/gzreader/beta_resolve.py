#!/usr/bin/env python3
"""Merge conflicts that combining PRs into the beta branch can settle alone
(tools/gzreader/beta-combine.sh). Exit 0 when every given file was settled,
1 when one can't be (the PR is then left out of beta).

- plugins/gzreader.koplugin/gzreader_changelog.lua: every PR adds lines to
  the "next" entry at the top: both sides' lines are kept (ours first).
- tools/gzreader/tests/keeps.txt: "<count> <file>" lines: every file kept,
  with the higher count.
- docs/sync/index.html: when the two sides differ only in gzsync.js's ?v=
  (every PR that changes the sync page's script changes it), the hash of the
  combined docs/sync/gzsync.js.

    beta_resolve.py <conflicted file>...
"""
import re
import sys

HUNK = re.compile(r"<<<<<<< [^\n]*\n(.*?)(?:\|\|\|\|\|\|\| [^\n]*\n.*?)?=======\n(.*?)>>>>>>> [^\n]*\n", re.S)


def changelog(text):
    out = HUNK.sub(lambda m: m.group(1) + m.group(2), text)
    return None if "<<<<<<<" in out or ">>>>>>>" in out else out


def keeps(text):
    def merge(m):
        counts = {}
        for side in (m.group(1), m.group(2)):
            for line in side.splitlines():
                n, _, path = line.partition(" ")
                if n.isdigit() and path:
                    counts[path] = max(counts.get(path, 0), int(n))
        return "".join("%d %s\n" % (counts[p], p) for p in sorted(counts))
    out = HUNK.sub(merge, text)
    if "<<<<<<<" in out or ">>>>>>>" in out:
        return None
    head = [l for l in out.splitlines() if l.startswith("#")]
    body = {}
    for l in out.splitlines():
        if l and not l.startswith("#"):
            n, _, path = l.partition(" ")
            body[path] = max(body.get(path, 0), int(n))
    return "\n".join(head + ["%d %s" % (body[p], p) for p in sorted(body)]) + "\n"


VPAT = re.compile(r"gzsync\.js\?v=[0-9a-f]+")


def sync_page(text):
    import hashlib
    try:
        with open("docs/sync/gzsync.js", "rb") as f:
            v = "gzsync.js?v=" + hashlib.sha256(f.read()).hexdigest()[:10]
    except OSError:
        return None

    class Other(Exception):
        pass

    def merge(m):
        if VPAT.sub("", m.group(1)) != VPAT.sub("", m.group(2)):
            raise Other()
        return VPAT.sub(v, m.group(1))
    try:
        out = HUNK.sub(merge, text)
    except Other:
        return None
    if "<<<<<<<" in out or ">>>>>>>" in out:
        return None
    return VPAT.sub(v, out)


RULES = {
    "plugins/gzreader.koplugin/gzreader_changelog.lua": changelog,
    "tools/gzreader/tests/keeps.txt": keeps,
    "docs/sync/index.html": sync_page,
}


def main(paths):
    ok = True
    for p in paths:
        rule = RULES.get(p)
        if not rule:
            print("can't settle", p)
            ok = False
            continue
        with open(p, encoding="utf-8") as f:
            text = f.read()
        out = rule(text)
        if out is None:
            print("can't settle", p)
            ok = False
            continue
        with open(p, "w", encoding="utf-8") as f:
            f.write(out)
        print("settled", p)
    return 0 if ok and paths else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
