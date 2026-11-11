#!/usr/bin/env python3
"""Merge conflicts that combining PRs into the beta branch can settle alone
(tools/gzreader/beta-combine.sh). Exit 0 when every given file was settled,
1 when one can't be (the PR is then left out of beta).

- plugins/gzreader.koplugin/gzreader_changelog.lua: every PR adds lines to
  the "next" entry at the top: both sides' lines are kept (ours first).
  Inside a merge it's rebuilt from the two sides (git's stages 2 and 3):
  ours (beta so far) as it is, plus the PR's own "next" lines that ours
  doesn't have yet, in ours' "next" entry (made at the top if there's
  none). So a PR still based on the previous release (main has a new
  released entry where the PR has its "next") goes in with a changelog
  that loads; after 1.28.0, 1.28.1 and 1.28.2 that case had put the
  released entry's header above the PRs' "next" headers and beta's
  changelog didn't load. A result whose entries aren't each `{ version
  = …, changes = { … }, }` isn't written: the PR is left out instead.
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


CHANGELOG = "plugins/gzreader.koplugin/gzreader_changelog.lua"


def stage(n, path):
    """A side of the merge in progress (2: ours, 3: theirs), or None."""
    import subprocess
    r = subprocess.run(["git", "show", ":%d:%s" % (n, path)], capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else None


def next_lines(text):
    """The lines of the "next" entry's changes (each change on one line)."""
    out, inside = [], False
    for line in text.split("\n"):
        s = line.strip()
        if s == 'version = "next",':
            inside = True
            continue
        if inside and (s.startswith("version = ") or s == "},"):
            break
        if inside and s and s != "changes = {":
            out.append(line)
    return out


def with_next(text, lines):
    """text with lines added at the end of its "next" entry (made at the top when missing)."""
    rows = text.split("\n")
    if not lines:
        return text
    for i, line in enumerate(rows):
        if line.strip() == 'version = "next",':
            j = i + 1
            while rows[j].strip() == "changes = {":
                j += 1
            while j < len(rows) and rows[j].strip() != "},":
                j += 1
            rows[j:j] = lines
            return "\n".join(rows)
    top = rows.index("return {") + 1
    rows[top:top] = ["    {", '        version = "next",', "        changes = {"] + lines + ["        },", "    },"]
    return "\n".join(rows)


def well_formed(text):
    """Every entry is `{`, `version = …,`, `changes = {` … `},`, `},` at the top level."""
    rows = text.split("\n")
    if "<<<<<<<" in text or ">>>>>>>" in text or "return {" not in rows:
        return False
    for i, line in enumerate(rows):
        if line.strip().startswith("version = "):
            if i < 1 or rows[i - 1] != "    {" or rows[i + 1].strip() != "changes = {":
                return False
    opens = sum(1 for r in rows if r == "    {")
    closes = sum(1 for r in rows if r == "    },")
    return opens == closes == sum(1 for r in rows if r.strip().startswith("version = "))


def changelog(text):
    ours, theirs = stage(2, CHANGELOG), stage(3, CHANGELOG)
    if ours is not None and theirs is not None:
        have = {line.strip() for line in ours.split("\n")}
        out = with_next(ours, [line for line in next_lines(theirs) if line.strip() not in have])
    else:
        out = HUNK.sub(lambda m: m.group(1) + m.group(2), text)
    return out if well_formed(out) else None


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
    CHANGELOG: changelog,
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
