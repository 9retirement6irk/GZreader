#!/usr/bin/env python3
"""publish-updates.sh against a local repository: the release and the test
build share the "updates" branch, each publish keeping the other's files,
one commit each time; the old beta-updates branch while it's still wanted."""
import json
import os
import shutil
import subprocess
import sys
import tempfile

TOOL = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "publish-updates.sh"))
passed = failed = 0


def check(cond, msg):
    global passed, failed
    passed, failed = (passed + 1, failed) if cond else (passed, failed + 1)
    print("  ok  " if cond else "  FAIL", msg)


def git(cwd, *a):
    return subprocess.run(["git"] + list(a), cwd=cwd, check=True, capture_output=True, text=True).stdout


def main():
    w = tempfile.mkdtemp(prefix="gz-upd-")
    try:
        remote = os.path.join(w, "remote.git")
        git(w, "init", "-q", "--bare", remote)
        env = dict(os.environ, REMOTE=remote)
        env.pop("LEGACY_BETA_BRANCH", None)

        def publish(kind, content, version, legacy=False):
            z = os.path.join(w, "u.zip")
            open(z, "wb").write(content)
            e = dict(env, LEGACY_BETA_BRANCH="1") if legacy else env
            return subprocess.run(["bash", TOOL, kind, z, version, "abc123"], cwd=w, env=e, capture_output=True, text=True)

        def files(branch):
            out = os.path.join(w, "look")
            shutil.rmtree(out, ignore_errors=True)
            git(w, "clone", "-q", "-b", branch, remote, out)
            names = sorted(f for f in os.listdir(out) if f != ".git")
            commits = git(out, "rev-list", "--count", "HEAD").strip()
            return {n: open(os.path.join(out, n), "rb").read() for n in names}, commits

        print("the updates branch: releases and test builds side by side")
        r = publish("release", b"RELEASE1", "1.26.5")
        f, n = files("updates")
        meta = json.loads(f.get("latest.json", b"{}"))
        check(r.returncode == 0 and sorted(f) == ["gzreader-update.zip", "latest.json"] and meta["version"] == "1.26.5"
              and meta["file"] == "gzreader-update.zip" and meta["size"] == 8, "a release: gzreader-update.zip and latest.json " + r.stderr[-200:])
        r = publish("beta", b"BETA-1", "1.26.5-beta.aaa", legacy=True)
        f, n = files("updates")
        bmeta = json.loads(f.get("latest-beta.json", b"{}"))
        check(r.returncode == 0 and f.get("gzreader-update.zip") == b"RELEASE1" and f.get("gzreader-beta-update.zip") == b"BETA-1"
              and bmeta["file"] == "gzreader-beta-update.zip" and bmeta["version"] == "1.26.5-beta.aaa" and bmeta["commit"] == "abc123"
              and n == "1", "a test build: gzreader-beta-update.zip and latest-beta.json next to the release's, one commit")
        lf, _ = files("beta-updates")
        check(lf.get("gzreader-update.zip") == b"BETA-1" and json.loads(lf["latest.json"])["file"] == "gzreader-update.zip",
              "…and still on the old beta-updates branch, as test builds before this one read it")
        publish("release", b"RELEASE2", "1.26.6")
        f, n = files("updates")
        check(f.get("gzreader-update.zip") == b"RELEASE2" and json.loads(f["latest.json"])["version"] == "1.26.6"
              and f.get("gzreader-beta-update.zip") == b"BETA-1" and n == "1", "the next release: the test build kept")
        publish("beta", b"BETA-2", "1.26.6-beta.bbb")
        f, n = files("updates")
        check(f.get("gzreader-beta-update.zip") == b"BETA-2" and f.get("gzreader-update.zip") == b"RELEASE2",
              "the next test build: the release kept")
    finally:
        shutil.rmtree(w, ignore_errors=True)
    print("%d passed, %d failed" % (passed, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
