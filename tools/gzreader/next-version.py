#!/usr/bin/env python3
"""The version for a new GZreader release: the date, as year.month.day.

    tools/gzreader/next-version.py                 # e.g. 2026.11.21
    tools/gzreader/next-version.py --date 2026-11-21
    tools/gzreader/next-version.py --write         # also puts it in GZREADER_VERSION

Releases are named for the day they're made (2026.11.21, tagged v2026.11.21),
month and day with two digits. A second release on the same day adds .2, a
third .3 (2026.11.21.2). The day is the owner's (America/New_York), so an
evening release isn't named for tomorrow.

The tags already made are read from git (`git tag -l 'v*'`); --tags gives
them instead (for tests). Every place that compares versions (the updater,
the What's new screen, the sync page, the release notes) compares the
numbers one by one, so 2026.11.21 comes after 1.35.0 and 2026.11.21.2 after
2026.11.21; a test build of it is 2026.11.21-beta.<commit>.

Only the merging session and the owner use this: on a branch, leave
GZREADER_VERSION alone.
"""
import argparse
import datetime
import os
import re
import subprocess
import sys

ZONE = "America/New_York"
DATE_VERSION = re.compile(r"^(\d{4})\.(\d{2})\.(\d{2})(?:\.(\d+))?$")


def today(zone=ZONE):
    try:
        from zoneinfo import ZoneInfo
        return datetime.datetime.now(ZoneInfo(zone)).date()
    except Exception:  # no time zone data: the machine's own date
        return datetime.date.today()


def base(day):
    return "%04d.%02d.%02d" % (day.year, day.month, day.day)


def next_version(day, tags):
    """`day`'s version, given the tags (or versions) already made."""
    name = base(day)
    taken = set()
    for t in tags:
        v = re.sub(r"^[vV]\.?", "", t.strip())
        m = DATE_VERSION.match(v)
        if m and v.startswith(name):
            taken.add(int(m.group(4) or 1))
    if not taken:
        return name
    return "%s.%d" % (name, max(taken) + 1)


def is_date_version(v):
    return bool(DATE_VERSION.match(re.sub(r"^[vV]\.?", "", v.strip())))


def git_tags(root):
    try:
        out = subprocess.run(["git", "-C", root, "tag", "-l", "v*"], capture_output=True, text=True, check=True).stdout
    except (OSError, subprocess.CalledProcessError):
        return []
    return out.split()


def main(argv=None):
    root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--date", help="the day, YYYY-MM-DD (default: today in %s)" % ZONE)
    ap.add_argument("--tags", nargs="*", help="tags already made (default: git tag -l 'v*')")
    ap.add_argument("--write", action="store_true", help="write it into GZREADER_VERSION")
    a = ap.parse_args(argv)
    day = datetime.date.fromisoformat(a.date) if a.date else today()
    tags = a.tags if a.tags is not None else git_tags(root)
    v = next_version(day, tags)
    if a.write:
        with open(os.path.join(root, "GZREADER_VERSION"), "w") as f:
            f.write(v + "\n")
    print(v)
    return 0


if __name__ == "__main__":
    sys.exit(main())
