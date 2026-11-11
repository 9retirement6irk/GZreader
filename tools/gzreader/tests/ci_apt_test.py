#!/usr/bin/env python3
"""tools/gzreader/ci-apt.sh: CI's package installs fall back to a mirror
outside ubuntu.com when Ubuntu's servers can't be reached (2026-11-11:
GitHub's runners couldn't resolve azure.archive.ubuntu.com for hours).

apt-get, the name lookup and /etc/apt are stand-ins: the fake apt-get
"installs" only when a source file names a URI that works, and records
what it was asked.

    python3 tools/gzreader/tests/ci_apt_test.py
"""
import glob
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
SCRIPT = os.path.join(REPO, "tools", "gzreader", "ci-apt.sh")

passed = failed = 0


def check(ok, what):
    global passed, failed
    if ok:
        passed += 1
    else:
        failed += 1
        print("FAIL " + what)


FAKE_APT = r"""#!/bin/bash
echo "$*" >> "$FAKE_LOG"
case " $* " in *" update "*) exit 0 ;; esac
for f in "$GZ_APT_ETC"/sources.list.d/*.sources "$GZ_APT_ETC"/sources.list.d/*.list "$GZ_APT_ETC"/sources.list; do
  [ -f "$f" ] || continue
  for good in $FAKE_GOOD; do grep -q -- "$good" "$f" && exit 0; done
done
exit 100
"""

FAKE_RESOLVE = r"""#!/bin/bash
for h in $FAKE_RESOLVES; do [ "$h" = "$1" ] && exit 0; done
exit 2
"""

RUNNER_SOURCES = """Types: deb
URIs: mirror+file:/etc/apt/apt-mirrors.txt
Suites: noble noble-updates noble-backports
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: http://security.ubuntu.com/ubuntu
Suites: noble-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
"""

MIRROR_LIST = """http://azure.archive.ubuntu.com/ubuntu/\tpriority:1
https://archive.ubuntu.com/ubuntu/\tpriority:2
https://security.ubuntu.com/ubuntu/\tpriority:3
"""

MICROSOFT = "deb [arch=amd64] https://packages.microsoft.com/ubuntu/24.04/prod noble main\n"

MIRRORS = "https://mirror-a.example.com/ubuntu/ https://mirror-b.example.com/ubuntu/"


def run(resolves, good, packages=("luajit", "rsync")):
    d = tempfile.mkdtemp(prefix="ci-apt-")
    etc = os.path.join(d, "etc")
    os.makedirs(os.path.join(etc, "sources.list.d"))
    with open(os.path.join(etc, "sources.list"), "w") as f:
        f.write("# Ubuntu sources have moved to /etc/apt/sources.list.d/ubuntu.sources\n")
    with open(os.path.join(etc, "sources.list.d", "ubuntu.sources"), "w") as f:
        f.write(RUNNER_SOURCES)
    with open(os.path.join(etc, "sources.list.d", "microsoft-prod.list"), "w") as f:
        f.write(MICROSOFT)
    with open(os.path.join(etc, "apt-mirrors.txt"), "w") as f:
        f.write(MIRROR_LIST)
    bins = os.path.join(d, "bin")
    os.makedirs(bins)
    for name, src in (("apt-get", FAKE_APT), ("resolve", FAKE_RESOLVE)):
        p = os.path.join(bins, name)
        with open(p, "w") as f:
            f.write(src)
        os.chmod(p, 0o755)
    log = os.path.join(d, "apt.log")
    open(log, "w").close()
    env = dict(os.environ,
               GZ_APT_SUDO="", GZ_APT_GET=os.path.join(bins, "apt-get"),
               GZ_APT_RESOLVE=os.path.join(bins, "resolve"), GZ_APT_ETC=etc,
               GZ_APT_KEYRING="/usr/share/keyrings/ubuntu-archive-keyring.gpg",
               GZ_APT_CODENAME="noble", GZ_APT_MIRRORS=MIRRORS,
               FAKE_LOG=log, FAKE_RESOLVES=" ".join(resolves), FAKE_GOOD=" ".join(good))
    r = subprocess.run(["bash", SCRIPT] + list(packages), env=env, capture_output=True, text=True, timeout=60)
    calls = open(log).read().splitlines()
    files = sorted(os.path.relpath(p, etc) for p in glob.glob(os.path.join(etc, "**"), recursive=True) if os.path.isfile(p))
    mirror = os.path.join(etc, "sources.list.d", "gz-mirror.sources")
    mirror_text = open(mirror).read() if os.path.exists(mirror) else None
    return r, calls, files, mirror_text


UBUNTU_HOSTS = ["azure.archive.ubuntu.com", "archive.ubuntu.com", "security.ubuntu.com"]
EVERYWHERE = UBUNTU_HOSTS + ["mirror-a.example.com", "mirror-b.example.com"]

# Ubuntu's servers work: the runner's own sources, nothing changed
r, calls, files, mirror = run(EVERYWHERE, ["apt-mirrors.txt"])
check(r.returncode == 0, "Ubuntu reachable: installed (%d) %s" % (r.returncode, r.stdout + r.stderr))
check(mirror is None and "sources.list.d/ubuntu.sources" in files, "Ubuntu reachable: sources left as they are (%s)" % files)
check(len([c for c in calls if " install " in " " + c + " "]) == 1, "Ubuntu reachable: one install (%s)" % calls)
check(any(c.endswith("install -y -qq luajit rsync") for c in calls), "the packages asked for are installed (%s)" % calls)
check("::notice::" not in r.stdout, "Ubuntu reachable: no notice")

# Ubuntu's servers don't resolve (2026-11-11): straight to the first mirror, no slow attempt
r, calls, files, mirror = run(["mirror-a.example.com", "mirror-b.example.com"], ["mirror-a.example.com"])
check(r.returncode == 0, "no Ubuntu: installed from a mirror (%d) %s" % (r.returncode, r.stdout + r.stderr))
check(len([c for c in calls if "install" in c]) == 1, "no Ubuntu: the runner's sources not tried first (%s)" % calls)
check("sources.list.d/ubuntu.sources.gz-aside" in files and "sources.list.d/ubuntu.sources" not in files,
      "no Ubuntu: Ubuntu's sources set aside (%s)" % files)
check("sources.list.d/microsoft-prod.list" in files, "other sources left alone (%s)" % files)
check("sources.list" in files, "a sources.list with comments only is left alone (%s)" % files)
check(mirror is not None and "URIs: https://mirror-a.example.com/ubuntu/" in mirror, "the first mirror is used (%s)" % mirror)
check(mirror is not None and "Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg" in mirror,
      "a mirror's packages are still checked against Ubuntu's key (%s)" % mirror)
check(mirror is not None and re.search(r"^Suites: noble noble-updates noble-backports noble-security$", mirror, re.M) is not None,
      "a mirror carries the release, updates, backports and security (%s)" % mirror)
check("::notice::Ubuntu packages came from https://mirror-a.example.com/ubuntu/" in r.stdout,
      "the log says which mirror was used (%s)" % r.stdout)
check("does not resolve" in r.stdout, "the log says Ubuntu's servers didn't resolve (%s)" % r.stdout)

# Ubuntu resolves but the install fails anyway: a mirror after it
r, calls, files, mirror = run(EVERYWHERE, ["mirror-a.example.com"])
check(r.returncode == 0, "Ubuntu failing: installed from a mirror (%d)" % r.returncode)
check(len([c for c in calls if " install " in " " + c + " "]) == 2, "Ubuntu failing: the runner's sources first, then the mirror (%s)" % calls)

# The first mirror fails too: the next one
r, calls, files, mirror = run(["mirror-a.example.com", "mirror-b.example.com"], ["mirror-b.example.com"])
check(r.returncode == 0, "first mirror failing: the second one (%d) %s" % (r.returncode, r.stdout))
check(mirror is not None and "mirror-b.example.com" in mirror and "mirror-a" not in mirror, "first mirror failing: the second one written (%s)" % mirror)

# A mirror whose name doesn't resolve isn't even tried
r, calls, files, mirror = run(["mirror-b.example.com"], ["mirror-b.example.com"])
check(r.returncode == 0 and len([c for c in calls if " install " in " " + c + " "]) == 1,
      "an unresolvable mirror is skipped without an install (%d, %s)" % (r.returncode, calls))

# Nothing works: CI fails, saying so
r, calls, files, mirror = run(EVERYWHERE, [])
check(r.returncode != 0, "nothing reachable: fails (%d)" % r.returncode)
check("::error::" in r.stdout, "nothing reachable: says so (%s)" % r.stdout)

# No packages named: an error, nothing touched
r, calls, files, mirror = run(EVERYWHERE, ["apt-mirrors.txt"], packages=())
check(r.returncode != 0 and calls == [], "no packages: an error, apt not run (%d, %s)" % (r.returncode, calls))

# Every workflow installs through it (no apt-get install of its own)
wf_dir = os.path.join(REPO, ".github", "workflows")
for wf in sorted(glob.glob(os.path.join(wf_dir, "*.yml"))):
    text = open(wf).read()
    name = os.path.basename(wf)
    raw = [l for l in text.splitlines() if re.search(r"apt-get (update|install)", l) and "ci-apt.sh" not in l
           and not l.strip().startswith("#")]
    # an old tag (release notes by hand, a release run again) has no ci-apt.sh: a plain apt-get only in its else branch
    fallback_only = all(l.strip().startswith("else ") for l in raw) and "[ -f tools/gzreader/ci-apt.sh ]" in text
    check(not raw or fallback_only, "%s: apt-get only through ci-apt.sh (%s)" % (name, raw))
    if "apt-get" in text or "ci-apt.sh" in text:
        check("ci-apt.sh" in text, "%s uses ci-apt.sh" % name)

print("%d passed, %d failed" % (passed, failed))
sys.exit(1 if failed else 0)
