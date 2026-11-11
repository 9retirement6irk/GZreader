#!/usr/bin/env python3
"""beta_resolve.py: the conflicts combining PRs into beta settles alone."""
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "..", "beta_resolve.py")
passed = failed = 0


def check(cond, msg):
    global passed, failed
    passed, failed = (passed + 1, failed) if cond else (passed, failed + 1)
    print("  ok  " if cond else "  FAIL", msg)


def run(files, conflicted=None):
    d = tempfile.mkdtemp()
    for rel, text in files.items():
        os.makedirs(os.path.join(d, os.path.dirname(rel)), exist_ok=True)
        with open(os.path.join(d, rel), "w") as f:
            f.write(text)
    r = subprocess.run([sys.executable, TOOL] + list(conflicted or files), cwd=d, capture_output=True, text=True)
    out = {rel: open(os.path.join(d, rel)).read() for rel in files}
    return r.returncode, out


print("beta: conflicts settled alone")
CL = "plugins/gzreader.koplugin/gzreader_changelog.lua"
rc, out = run({CL: 'return {\n    {\n        version = "next",\n        changes = {\n<<<<<<< HEAD\n            "A",\n            "B",\n=======\n            "C",\n>>>>>>> feat/c\n        },\n    },\n}\n'})
check(rc == 0 and '"A",\n            "B",\n            "C",\n        },' in out[CL] and "<<<" not in out[CL], "changelog: both sides' next lines kept, ours first")
KT = "tools/gzreader/tests/keeps.txt"
rc, out = run({KT: "# marks\n1 a.lua\n<<<<<<< HEAD\n5 b.lua\n2 c.lua\n=======\n7 b.lua\n3 d.lua\n>>>>>>> x\n9 e.lua\n"})
check(rc == 0 and out[KT] == "# marks\n1 a.lua\n7 b.lua\n2 c.lua\n3 d.lua\n9 e.lua\n", "keeps.txt: every file, the higher count")
import hashlib
SP, SJ = "docs/sync/index.html", "docs/sync/gzsync.js"
js = "var combined = 1;\n"
want = hashlib.sha256(js.encode()).hexdigest()[:10]
rc, out = run(conflicted=[SP], files={SJ: js, SP: '<p>page</p>\n<<<<<<< HEAD\n<script src="gzsync.js?v=1111111111"></script><!-- note -->\n=======\n<script src="gzsync.js?v=2222222222"></script><!-- note -->\n>>>>>>> x\n<p>end</p>\n'})
check(rc == 0 and out[SP] == '<p>page</p>\n<script src="gzsync.js?v=%s"></script><!-- note -->\n<p>end</p>\n' % want,
      "sync page: two PRs' ?v= of gzsync.js: the combined script's hash")
rc, out = run(conflicted=[SP], files={SJ: js, SP: '<<<<<<< HEAD\n<script src="gzsync.js?v=1111111111"></script><b>a</b>\n=======\n<script src="gzsync.js?v=2222222222"></script><b>b</b>\n>>>>>>> x\n'})
check(rc == 1, "sync page: anything else different too: not settled")
rc, out = run({"plugins/gzreader.koplugin/main.lua": "<<<<<<< HEAD\na\n=======\nb\n>>>>>>> x\n"})
check(rc == 1 and "<<<<<<<" in out["plugins/gzreader.koplugin/main.lua"], "any other file: not settled (the PR is left out), left as it was")
rc, out = run({CL: "<<<<<<< HEAD\na\n=======\nb\n>>>>>>> x\n", "frontend/x.lua": "<<<<<<< HEAD\na\n=======\nb\n>>>>>>> x\n"})
check(rc == 1, "a changelog clash with another file's: not settled")


def git(d, *a):
    return subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@example.com", "-c", "commit.gpgsign=false", *a], cwd=d, capture_output=True, text=True)


def entry(version, *lines):
    return "    {\n        version = \"%s\",\n        changes = {\n%s        },\n    },\n" % (
        version, "".join('            { short = "%s", text = "%s" },\n' % (l, l) for l in lines))


def merged_changelog(base, ours, theirs):
    """git merge of theirs into ours (both from base), the tool on the clash: (rc, file, loads)."""
    d = tempfile.mkdtemp()
    os.makedirs(os.path.join(d, os.path.dirname(CL)))
    path = os.path.join(d, CL)
    git(d, "init", "-q", "-b", "main")
    for name, text in (("base", base), ("ours", ours), ("theirs", theirs)):
        if name != "base":
            git(d, "checkout", "-q", "-B", name, "base")
        open(path, "w").write(text)
        git(d, "add", CL)
        git(d, "commit", "-q", "-m", name)
        if name == "base":
            git(d, "branch", "base")
    git(d, "checkout", "-q", "ours")
    m = git(d, "merge", "-q", "--no-edit", "theirs")
    if m.returncode == 0:
        return "clean", open(path).read(), None
    r = subprocess.run([sys.executable, TOOL, CL], cwd=d, capture_output=True, text=True)
    out = open(path).read()
    lj = subprocess.run(["luajit", "-e", "local t = assert(loadfile(os.getenv('CL_PATH')))(); for _, e in ipairs(t) do io.write(e.version, '=', #e.changes, ' ') end"],
                        capture_output=True, text=True, env=dict(os.environ, CL_PATH=path))
    return r.returncode, out, (lj.stdout.strip() if lj.returncode == 0 else None)


HEAD_ = "-- GZreader changelog\nreturn {\n"
REL = entry("1.28.1", "one", "two")
# main released 1.28.2 where the PR (still on 1.28.1) has its "next" (1.28.0, 1.28.1, 1.28.2: beta's changelog didn't load)
rc, out, loads = merged_changelog(HEAD_ + REL + "}\n", HEAD_ + entry("1.28.2", "released") + REL + "}\n",
                                  HEAD_ + entry("next", "pr line") + REL + "}\n")
check(rc == 0 and loads == "next=1 1.28.2=1 1.28.1=2", "changelog: a PR on the previous release after a new one: next on top, then the releases, and it loads (%s, %s)" % (rc, loads))
check(out.index('"pr line"') < out.index('"1.28.2"') and "<<<" not in out, "…the PR's line in next, above the new release")
# beta already has a next (an earlier PR), on top of the new release: the PR's line added to it
rc, out, loads = merged_changelog(HEAD_ + REL + "}\n",
                                  HEAD_ + entry("next", "earlier pr") + entry("1.28.2", "released") + REL + "}\n",
                                  HEAD_ + entry("next", "pr line") + REL + "}\n")
check(rc == 0 and loads == "next=2 1.28.2=1 1.28.1=2" and out.index('"earlier pr"') < out.index('"pr line"'),
      "changelog: added to beta's next (ours first) above the new release (%s, %s)" % (rc, loads))
# a PR built on another: its lines already in beta aren't repeated
rc, out, loads = merged_changelog(HEAD_ + entry("next", "x") + REL + "}\n",
                                  HEAD_ + entry("next", "x", "a") + REL + "}\n",
                                  HEAD_ + entry("next", "x", "a", "b") + REL + "}\n")
check(rc in ("clean", 0) and out.count('"a"') == 2 and out.count('"b"') == 2, "changelog: a line both sides have stays once (%s)" % rc)
# the text-only way (outside a merge) still refuses what wouldn't load
rc, out = run({CL: 'return {\n    {\n<<<<<<< HEAD\n        version = "1.28.2",\n        changes = {\n            "A",\n=======\n        version = "next",\n        changes = {\n            "B",\n>>>>>>> x\n        },\n    },\n}\n'})
check(rc == 1, "changelog: a result whose entries aren't whole isn't written: the PR is left out")

print("%d passed, %d failed" % (passed, failed))
sys.exit(1 if failed else 0)
