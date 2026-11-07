#!/usr/bin/env python3
"""beta-combine.sh with a pretend GitHub: a local repository as origin and a
stand-in gh (pull requests, comments, workflow runs). Checks: beta = main +
the labelled pull requests in order (changelog clashes settled); one that
clashes elsewhere is left out with one comment per commit; unlabelled ones
stay out; nothing pushed when beta wouldn't change; after a push the test
build, the Nook package and the tests are started on beta."""
import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.abspath(os.path.join(HERE, ".."))
passed = failed = 0


def check(cond, msg):
    global passed, failed
    passed, failed = (passed + 1, failed) if cond else (passed, failed + 1)
    print("  ok  " if cond else "  FAIL", msg)


def git(cwd, *args):
    return subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@example.com"] + list(args), cwd=cwd,
                          check=True, capture_output=True, text=True).stdout.strip()


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)


CL = "plugins/gzreader.koplugin/gzreader_changelog.lua"
CL_MAIN = 'return {\n    {\n        version = "next",\n        changes = {\n        },\n    },\n}\n'


def main():
    w = tempfile.mkdtemp(prefix="gz-beta-")
    try:
        origin = os.path.join(w, "origin.git")
        git(w, "init", "-q", "--bare", "-b", "main", origin)
        src = os.path.join(w, "src")
        git(w, "clone", "-q", origin, src)
        write(os.path.join(src, CL), CL_MAIN)
        write(os.path.join(src, "main.lua"), "print('main')\n")
        os.makedirs(os.path.join(src, "tools/gzreader"))
        for f in ("beta-combine.sh", "beta_resolve.py"):
            shutil.copy(os.path.join(TOOLS, f), os.path.join(src, "tools/gzreader", f))
        git(src, "add", "-A"); git(src, "commit", "-qm", "main"); git(src, "push", "-q", "origin", "main")

        def branch(name, files, line):
            git(src, "checkout", "-q", "-b", name, "main")
            for p, t in files.items():
                write(os.path.join(src, p), t)
            write(os.path.join(src, CL), CL_MAIN.replace("changes = {\n", 'changes = {\n            "%s",\n' % line))
            git(src, "add", "-A"); git(src, "commit", "-qm", name); git(src, "push", "-q", "origin", name)
            git(src, "checkout", "-q", "main")
            return git(src, "rev-parse", name)

        sha = {
            "a": branch("feat/a", {"a.lua": "a\n"}, "A"),
            "b": branch("feat/b", {"b.lua": "b\n"}, "B"),
            "c": branch("fix/c", {"main.lua": "print('c')\n"}, "C"),
            "d": branch("fix/d", {"main.lua": "print('d')\n"}, "D"),
            "e": branch("feat/e", {"e.lua": "e\n"}, "E"),
        }
        repo = "owner/gz"
        pulls = [
            {"number": 3, "head": {"ref": "feat/a", "sha": sha["a"], "repo": {"full_name": repo}}, "labels": [{"name": "beta"}]},
            {"number": 4, "head": {"ref": "feat/b", "sha": sha["b"], "repo": {"full_name": repo}}, "labels": [{"name": "beta"}]},
            {"number": 5, "head": {"ref": "fix/c", "sha": sha["c"], "repo": {"full_name": repo}}, "labels": [{"name": "beta"}]},
            {"number": 6, "head": {"ref": "fix/d", "sha": sha["d"], "repo": {"full_name": repo}}, "labels": [{"name": "beta"}]},
            {"number": 7, "head": {"ref": "feat/e", "sha": sha["e"], "repo": {"full_name": repo}}, "labels": []},
        ]
        state = os.path.join(w, "gh-state")
        os.makedirs(state)
        with open(os.path.join(state, "pulls.json"), "w") as f:
            json.dump(pulls, f)
        # the stand-in gh: pulls list (with --jq through jq-like python), comments, workflow runs
        bindir = os.path.join(w, "bin")
        os.makedirs(bindir)
        write(os.path.join(bindir, "gh"), """#!/usr/bin/env python3
import json, os, sys
st = %r
a = sys.argv[1:]
def jq(data, expr):
    # (the two queries beta-combine.sh makes)
    if "select(any(.labels[]" in expr:
        prs = [p for p in data if any(l["name"] == "beta" for l in p["labels"]) and p["head"]["repo"]["full_name"] == "owner/gz"]
        return "\\n".join("%%d %%s %%s" %% (p["number"], p["head"]["ref"], p["head"]["sha"]) for p in sorted(prs, key=lambda p: p["number"]))
    if expr == ".[].body":
        return "\\n".join(c["body"] for c in data)
    raise SystemExit("jq? " + expr)
if a[0] == "api":
    path = [x for x in a[1:] if not x.startswith("-") and "/" in x][0]
    if "-X" in a:
        n = path.split("/")[-2]
        body = a[a.index("-f") + 1].split("=", 1)[1]
        with open(os.path.join(st, "comments-%%s.json" %% n), "a") as f: f.write(json.dumps(body) + "\\n")
        sys.exit(0)
    if "/pulls" in path:
        data = json.load(open(os.path.join(st, "pulls.json")))
    else:
        n = path.split("/")[-2]
        p = os.path.join(st, "comments-%%s.json" %% n)
        data = [{"body": json.loads(l)} for l in open(p)] if os.path.exists(p) else []
    print(jq(data, a[a.index("--jq") + 1]))
elif a[0] == "workflow" and a[1] == "run":
    with open(os.path.join(st, "runs.txt"), "a") as f: f.write(a[2] + " " + a[a.index("--ref") + 1] + "\\n")
""" % state)
        os.chmod(os.path.join(bindir, "gh"), 0o755)
        work = os.path.join(w, "work")
        git(w, "clone", "-q", origin, work)
        env = dict(os.environ, PATH=bindir + os.pathsep + os.environ["PATH"], GITHUB_REPOSITORY=repo, RUNNER_TEMP=w,
                   GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@example.com", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@example.com")

        def combine():
            return subprocess.run(["bash", "tools/gzreader/beta-combine.sh"], cwd=work, env=env, capture_output=True, text=True, timeout=60)

        def runs():
            p = os.path.join(state, "runs.txt")
            return open(p).read().split("\n")[:-1] if os.path.exists(p) else []

        def comments(n):
            p = os.path.join(state, "comments-%d.json" % n)
            return [json.loads(l) for l in open(p)] if os.path.exists(p) else []

        print("beta: labelled pull requests combined")
        r = combine()
        check(r.returncode == 0 and "beta = main + #3 #4 #5 (left out: #6)" in r.stdout, "beta = main + the labelled ones in order; a clash left out (%s%s)" % (r.stdout.strip(), r.stderr.strip()[-300:]))
        files = git(origin, "ls-tree", "-r", "--name-only", "beta").split("\n")
        main_lua = git(origin, "show", "beta:main.lua")
        cl = git(origin, "show", "beta:" + CL)
        check("a.lua" in files and "b.lua" in files and main_lua == "print('c')" and "e.lua" not in files,
              "their changes are on beta (the unlabelled one's aren't)")
        check('"A",' in cl and '"B",' in cl and '"C",' in cl and '"D"' not in cl and "<<<" not in cl,
              "the changelog's next lines from all of them, clashes settled")
        c6 = comments(6)
        check(len(c6) == 1 and "main.lua" in c6[0] and "beta-combine:%s" % sha["d"] in c6[0] and not comments(5),
              "the left-out one gets a comment naming the clashing file")
        check(runs() == ["gzreader-beta.yml beta", "gzreader-nook.yml beta", "gzreader-tests.yml beta"],
              "after the push: the test build, the Nook package and the tests started on beta")
        before = git(origin, "rev-parse", "beta")
        r = combine()
        check(r.returncode == 0 and "unchanged" in r.stdout and git(origin, "rev-parse", "beta") == before and len(runs()) == 3
              and len(comments(6)) == 1, "again with nothing new: nothing pushed, nothing started, no second comment")
        pulls[1]["labels"] = []
        with open(os.path.join(state, "pulls.json"), "w") as f:
            json.dump(pulls, f)
        r = combine()
        files = git(origin, "ls-tree", "-r", "--name-only", "beta").split("\n")
        check(r.returncode == 0 and "b.lua" not in files and "a.lua" in files and len(runs()) == 6, "a pull request unlabelled: out of beta, built again")
    finally:
        shutil.rmtree(w, ignore_errors=True)
    print("%d passed, %d failed" % (passed, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
