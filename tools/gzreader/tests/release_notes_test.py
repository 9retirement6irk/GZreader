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
        check("gzreader-kindle-legacy-1.10.2.zip" in out and "gzreader-nook-1st-edition-1.10.2.zip" in out,
              "which package to download, by name")
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
    print("%d passed, %d failed" % (passed, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
