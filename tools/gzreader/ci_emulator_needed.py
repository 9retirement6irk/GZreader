#!/usr/bin/env python3
"""Does a change need the emulator runs in CI (GZreader started under qemu on
every model, ~25 minutes)? Reads the changed files' paths, one per line, on
stdin, and prints "needed" or "skip".

"skip" only when every file is one the emulator can't be affected by: the
web pages in docs/ (the landing page, the sync page: they never reach a
device), Markdown, the device's changelog (a data table: luacheck and the
plugin tests still read it), the tests (except make_epub.py, which makes
the emulator's books), and the publishing side of CI: the workflows and
scripts that make the beta branch, publish updates, releases and their
notes, the wiki, and the Nook build's workflow (they run after the tests, on GitHub,
and change no file GZreader runs; the packaging scripts that make what a
device installs are not among them). Anything else, an empty list, the
tests' own workflow, ci-test.sh or this file itself: "needed". The tests themselves (tools/gzreader/tests/run.sh) always run.

    git diff --name-only HEAD^1 HEAD | python3 tools/gzreader/ci_emulator_needed.py
"""
import sys

NEEDED_IN_TESTS = {"tools/gzreader/tests/make_epub.py"}

# CI's publishing side: nothing here is in what the emulator starts
PUBLISHING = {
    ".github/workflows/gzreader-beta.yml",
    ".github/workflows/gzreader-beta-combine.yml",
    ".github/workflows/gzreader-release.yml",
    ".github/workflows/gzreader-release-notes.yml",
    ".github/workflows/gzreader-nook.yml",
    ".github/workflows/gzreader-upstream.yml",
    ".github/workflows/gzreader-wiki.yml",
    "tools/gzreader/publish-updates.sh",
    "tools/gzreader/publish-github-release.sh",
    "tools/gzreader/beta-combine.sh",
    "tools/gzreader/beta_resolve.py",
    "tools/gzreader/release-notes.lua",
    "tools/gzreader/upstream.sh",
}


def skippable(path):
    if path in NEEDED_IN_TESTS:
        return False
    return (path in PUBLISHING
            or path.startswith("docs/")
            or path.endswith(".md")
            or path == "plugins/gzreader.koplugin/gzreader_changelog.lua"
            or path.startswith("tools/gzreader/tests/"))


def decide(paths):
    paths = [p.strip() for p in paths if p.strip()]
    return "skip" if paths and all(skippable(p) for p in paths) else "needed"


if __name__ == "__main__":
    print(decide(sys.stdin.read().splitlines()))
