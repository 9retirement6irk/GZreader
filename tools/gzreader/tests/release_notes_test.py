#!/usr/bin/env python3
"""Release notes from the changelog (tools/gzreader/release-notes.lua).

    python3 tools/gzreader/tests/release_notes_test.py
"""
import os
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


def notes(*args, changelog=None):
    r = subprocess.run(["luajit", os.path.join(REPO, "tools", "gzreader", "release-notes.lua"), changelog] + list(args),
                       capture_output=True, text=True, timeout=30)
    return r.returncode, r.stdout, r.stderr


def main():
    with tempfile.TemporaryDirectory() as d:
        cl = os.path.join(d, "changelog.lua")
        open(cl, "w").write('return {\n'
                            '  { version = "next", changes = { "Not released yet." } },\n'
                            '  { version = "1.10.2", changes = { "Ten two, a fix.", "Ten two, a feature\\nover two lines." } },\n'
                            '  { version = "1.10.1", changes = { "Ten one.", { short = "Short", text = "Ten one, the long text." } } },\n'
                            '  { version = "1.9.0", changes = { "Nine." } },\n'
                            '  { version = "1.8.5", changes = { "Eight five." } },\n'
                            '}\n')
        print("Release notes")
        rc, out, err = notes("v1.10.2", "v1.10.2", "v1.9.0", "v1.8.5", changelog=cl)
        check(rc == 0 and "### 1.10.2" in out and "### 1.10.1" in out and "Nine." not in out and "Not released" not in out
              and out.index("### 1.10.2") < out.index("### 1.10.1"),
              "every version since the previous release (1.9.0, not 1.10.0 by text order), newest first, not 'next' (%s)" % err.strip())
        check("- Ten two, a feature over two lines." in out and "Changes since v1.9.0" in out,
              "one line per change; says since which release")
        check("gzreader-kindle-legacy-1.10.2.zip" in out and "gzreader-nook-1st-edition-1.10.2.zip" in out
              and "gzreader-kobo-1.10.2.zip" in out,
              "which package to download, by name (the Kobo's too)")
        rc, out, _ = notes("1.10.1", "v1.10.2", "v1.10.1", "v1.9.0", changelog=cl)
        check(rc == 0 and "- Ten one, the long text." in out and "Short" not in out,
              "a { short, text } line: its full text")
        check(rc == 0 and "- Ten one." in out and "###  1.10.1" not in out and "Ten two" not in out and "Nine." not in out,
              "only its own entry when the release before it is the version before it")
        rc, out, _ = notes("1.9.0", changelog=cl)
        check(rc == 0 and "- Nine." in out and "Eight five" not in out, "no tags: its own entry")
        rc, out, _ = notes("2.0.0", "v1.10.2", changelog=cl)
        check(rc == 0 and "GZreader 2.0.0." in out, "a version the changelog doesn't have: a line, not nothing")
        rc, _, err = notes(changelog=cl)
        check(rc == 2 and "usage" in err, "no version: usage")

        # Releases named for the day (tools/gzreader/next-version.py): the first after 1.35.0 is a date
        dated = os.path.join(d, "dated.lua")
        open(dated, "w").write('return {\n'
                               '  { version = "next", changes = { "Not released yet." } },\n'
                               '  { version = "2026.11.21.2", changes = { "Same day, again." } },\n'
                               '  { version = "2026.11.21", changes = { "The first by date." } },\n'
                               '  { version = "1.35.0", changes = { "The last numbered." } },\n'
                               '}\n')
        print("Release notes: versions by date")
        rc, out, err = notes("v2026.11.21", "v2026.11.21", "v1.35.0", changelog=dated)
        check(rc == 0 and "- The first by date." in out and "The last numbered" not in out and "Changes since v1.35.0" in out
              and "gzreader-kindle-legacy-2026.11.21.zip" in out,
              "the first release by date comes after 1.35.0 (%s)" % err.strip())
        rc, out, _ = notes("v2026.11.21.2", "v2026.11.21.2", "v2026.11.21", "v1.35.0", changelog=dated)
        check(rc == 0 and "- Same day, again." in out and "The first by date" not in out and "Changes since v2026.11.21" in out,
              "a second release the same day (.2) comes after the first")

    print("Next version (next-version.py)")
    import importlib.util
    spec = importlib.util.spec_from_file_location("next_version", os.path.join(REPO, "tools", "gzreader", "next-version.py"))
    nv = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(nv)
    import datetime
    day = datetime.date(2026, 11, 21)
    check(nv.next_version(day, ["v1.35.0", "v1.34.0"]) == "2026.11.21", "a day's first release: year.month.day")
    check(nv.next_version(datetime.date(2027, 1, 5), []) == "2027.01.05", "month and day with two digits")
    check(nv.next_version(day, ["v2026.11.21"]) == "2026.11.21.2", "the same day again: .2")
    check(nv.next_version(day, ["v2026.11.21", "v2026.11.21.2", "v2026.11.20"]) == "2026.11.21.3", "and .3 after that")
    check(nv.next_version(day, ["v2026.11.210", "v2026.11.2"]) == "2026.11.21", "other days aren't counted")
    check(nv.is_date_version("v2026.11.21") and nv.is_date_version("2026.11.21.2") and not nv.is_date_version("1.35.0")
          and not nv.is_date_version("2026.11.21-beta.abc1234"), "what a date version looks like")
    r = subprocess.run([sys.executable, os.path.join(REPO, "tools", "gzreader", "next-version.py"), "--date", "2026-11-21",
                        "--tags", "v2026.11.21"], capture_output=True, text=True, timeout=30)
    check(r.returncode == 0 and r.stdout.strip() == "2026.11.21.2", "the script prints it (%s)" % r.stderr.strip())
    print("%d passed, %d failed" % (passed, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
