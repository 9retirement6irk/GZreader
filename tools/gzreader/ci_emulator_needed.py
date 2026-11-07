#!/usr/bin/env python3
"""Does a change need the emulator runs in CI (GZreader started under qemu on
every model, ~25 minutes)? Reads the changed files' paths, one per line, on
stdin, and prints "needed" or "skip".

"skip" only when every file is one the emulator can't be affected by: the
web pages in docs/ (the landing page, the sync page: they never reach a
device), Markdown, the device's changelog (a data table: luacheck and the
plugin tests still read it), and the tests (except make_epub.py, which makes
the emulator's books). Anything else, an empty list, or this file itself:
"needed". The tests themselves (tools/gzreader/tests/run.sh) always run.

    git diff --name-only HEAD^1 HEAD | python3 tools/gzreader/ci_emulator_needed.py
"""
import sys

NEEDED_IN_TESTS = {"tools/gzreader/tests/make_epub.py"}


def skippable(path):
    if path in NEEDED_IN_TESTS:
        return False
    return (path.startswith("docs/")
            or path.endswith(".md")
            or path == "plugins/gzreader.koplugin/gzreader_changelog.lua"
            or path.startswith("tools/gzreader/tests/"))


def decide(paths):
    paths = [p.strip() for p in paths if p.strip()]
    return "skip" if paths and all(skippable(p) for p in paths) else "needed"


if __name__ == "__main__":
    print(decide(sys.stdin.read().splitlines()))
