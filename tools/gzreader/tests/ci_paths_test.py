#!/usr/bin/env python3
"""ci_emulator_needed.py: which pull requests CI runs the emulator for."""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "..", "ci_emulator_needed.py")
passed = failed = 0


def check(cond, msg):
    global passed, failed
    passed, failed = (passed + 1, failed) if cond else (passed, failed + 1)
    print("  ok  " if cond else "  FAIL", msg)


def run(*paths):
    return subprocess.run([sys.executable, TOOL], input="\n".join(paths) + "\n", capture_output=True, text=True).stdout.strip()


page = ["docs/sync/gzsync.js", "docs/sync/index.html", "docs/sync/vendor/libheif-1.23.5.js",
        "tools/gzreader/tests/sync_page_test.py", "tools/gzreader/tests/run_tests.lua", "tools/gzreader/tests/media/picture.heic",
        "plugins/gzreader.koplugin/gzreader_changelog.lua", "GZREADER.md"]
check(run(*page) == "skip", "the sync page, its tests, the changelog and the docs: no emulator runs")
check(run(*page, "plugins/gzreader.koplugin/gzreader_usbsync.lua") == "needed", "…but with a plugin file: the emulator runs")
check(run("docs/index.html", "frontend/ui/widget/menu.lua") == "needed", "KOReader's frontend: the emulator runs")
check(run("tools/gzreader/tests/make_epub.py") == "needed", "the emulator's books (make_epub.py): it runs")
check(run("tools/gzreader/ci-test.sh") == "needed" and run(".github/workflows/gzreader-tests.yml") == "needed"
      and run("tools/gzreader/ci_emulator_needed.py") == "needed", "CI itself (and this decision): it runs")
check(run() == "needed" and run("", " ") == "needed", "nothing known to have changed: it runs")
check(run("tools/gzreader/emulator/keeps.lua") == "needed" and run("plugins/zenos.koplugin/main.lua") == "needed",
      "the emulator's checks, ZenOS: it runs")

ci = [".github/workflows/gzreader-nook.yml", ".github/workflows/gzreader-beta.yml", "tools/gzreader/publish-updates.sh",
      "tools/gzreader/tests/publish_updates_test.py"]
check(run(*ci) == "skip", "publishing updates and the Nook build's workflow, with their tests: no emulator runs")
check(run(".github/workflows/gzreader-beta-combine.yml", "tools/gzreader/beta-combine.sh", "tools/gzreader/beta_resolve.py",
          ".github/workflows/gzreader-release-notes.yml", "tools/gzreader/release-notes.lua",
          ".github/workflows/gzreader-release.yml", "tools/gzreader/publish-github-release.sh",
          ".github/workflows/gzreader-upstream.yml", "tools/gzreader/upstream.sh") == "skip",
      "the beta branch, releases and their notes, upstream checks: no emulator runs")
check(run(*ci, "tools/gzreader/package-kindle.sh") == "needed" and run("tools/gzreader/package-nook.sh") == "needed"
      and run("tools/gzreader/nook-runtime.sh") == "needed" and run("tools/gzreader/nook-softfloat/build-koreader.sh") == "needed",
      "…but what a device installs (the packaging scripts, the Nook's build): it runs")
check(run(*ci, ".github/workflows/gzreader-tests.yml") == "needed" and run(".github/workflows/build.yml") == "needed",
      "the tests' own workflow, KOReader's build: it runs")

print("\n%d passed, %d failed" % (passed, failed))
sys.exit(1 if failed else 0)
