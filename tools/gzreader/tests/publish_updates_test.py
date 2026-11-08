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

        print("the Nook's KOReader (no VFP) on the same branch")

        def publish_ko(name, content, version):
            z = os.path.join(w, name)
            open(z, "wb").write(content)
            return subprocess.run(["bash", TOOL, "nook-koreader", z, version, "abc123"], cwd=w, env=env, capture_output=True, text=True)

        r = publish_ko("koreader-kindle-legacy-v2026.07.1.zip", b"KO-1", "v2026.07.1")
        f, n = files("updates")
        kmeta = json.loads(f.get("nook-koreader.json", b"{}"))
        check(r.returncode == 0 and f.get("koreader-kindle-legacy-v2026.07.1.zip") == b"KO-1"
              and kmeta.get("file") == "koreader-kindle-legacy-v2026.07.1.zip" and kmeta.get("version") == "v2026.07.1"
              and f.get("gzreader-update.zip") == b"RELEASE2" and f.get("gzreader-beta-update.zip") == b"BETA-2"
              and "latest.json" in f and "latest-beta.json" in f and n == "1",
              "added next to the release and the test build, one commit " + r.stderr[-200:])
        publish_ko("koreader-kindle-legacy-v2026.07.2.zip", b"KO-2", "v2026.07.2")
        f, n = files("updates")
        check(f.get("koreader-kindle-legacy-v2026.07.2.zip") == b"KO-2" and "koreader-kindle-legacy-v2026.07.1.zip" not in f
              and f.get("gzreader-update.zip") == b"RELEASE2", "a newer KOReader replaces the old one")
        publish("beta", b"BETA-3", "1.26.6-beta.ccc")
        publish("release", b"RELEASE3", "1.26.7")
        f, n = files("updates")
        check(f.get("koreader-kindle-legacy-v2026.07.2.zip") == b"KO-2" and "nook-koreader.json" in f
              and f.get("gzreader-beta-update.zip") == b"BETA-3" and f.get("gzreader-update.zip") == b"RELEASE3",
              "test builds and releases keep it")
        r = publish_ko("something.zip", b"X", "v1")
        check(r.returncode != 0, "nook-koreader takes only koreader-kindle-legacy-<tag>.zip")

        print("two publishes at once")
        # (a pre-receive hook refuses the first push once)
        hook = os.path.join(remote, "hooks", "pre-receive")
        flag = os.path.join(w, "raced")
        open(hook, "w").write("#!/bin/sh\n"
                              "if [ ! -f '%s' ]; then touch '%s'\n"
                              "  exit 1\nfi\n" % (flag, flag))
        os.chmod(hook, 0o755)
        # (first push refused, as if another run had moved the branch: the
        # publish clones again and pushes)
        r = publish("beta", b"BETA-4", "1.26.7-beta.ddd")
        os.remove(hook)
        f, n = files("updates")
        check(r.returncode == 0 and f.get("gzreader-beta-update.zip") == b"BETA-4" and "again" in r.stderr
              and f.get("koreader-kindle-legacy-v2026.07.2.zip") == b"KO-2", "a refused push is tried again " + r.stderr[-200:])
        # a real race: the branch replaced after the clone → the lease refuses
        # the stale commit, the retry keeps the newcomer's files
        out = os.path.join(w, "o2")
        git(w, "clone", "-q", "-b", "updates", remote, out)
        lease_tool = os.path.join(w, "slow.sh")
        src = open(TOOL).read().replace('    cp "$ZIP" "$W/out/$FILE"\n',
                                         '    cp "$ZIP" "$W/out/$FILE"\n    [ -n "${GZ_TEST_RACE:-}" ] && { sh -c "$GZ_TEST_RACE"; GZ_TEST_RACE=; }\n', 1)
        open(lease_tool, "w").write(src)
        race = ("cd '%s' && echo NEW > newcomer.txt && git add newcomer.txt && "
                "git -c user.name=t -c user.email=t@example.com commit -qm n && git push -q '%s' updates" % (out, remote))
        z = os.path.join(w, "u.zip")
        open(z, "wb").write(b"BETA-5")
        r = subprocess.run(["bash", lease_tool, "beta", z, "1.26.7-beta.eee", "abc123"], cwd=w,
                           env=dict(env, GZ_TEST_RACE=race), capture_output=True, text=True)
        f, n = files("updates")
        check(r.returncode == 0 and f.get("newcomer.txt") == b"NEW\n" and f.get("gzreader-beta-update.zip") == b"BETA-5"
              and n == "1", "the branch changed meanwhile: not overwritten, published again on top " + r.stderr[-200:])
    finally:
        shutil.rmtree(w, ignore_errors=True)
    print("%d passed, %d failed" % (passed, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
