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


def run(files):
    d = tempfile.mkdtemp()
    for rel, text in files.items():
        os.makedirs(os.path.join(d, os.path.dirname(rel)), exist_ok=True)
        with open(os.path.join(d, rel), "w") as f:
            f.write(text)
    r = subprocess.run([sys.executable, TOOL] + list(files), cwd=d, capture_output=True, text=True)
    out = {rel: open(os.path.join(d, rel)).read() for rel in files}
    return r.returncode, out


print("beta: conflicts settled alone")
CL = "plugins/gzreader.koplugin/gzreader_changelog.lua"
rc, out = run({CL: 'return {\n    {\n        version = "next",\n        changes = {\n<<<<<<< HEAD\n            "A",\n            "B",\n=======\n            "C",\n>>>>>>> feat/c\n        },\n    },\n}\n'})
check(rc == 0 and '"A",\n            "B",\n            "C",\n        },' in out[CL] and "<<<" not in out[CL], "changelog: both sides' next lines kept, ours first")
KT = "tools/gzreader/tests/keeps.txt"
rc, out = run({KT: "# marks\n1 a.lua\n<<<<<<< HEAD\n5 b.lua\n2 c.lua\n=======\n7 b.lua\n3 d.lua\n>>>>>>> x\n9 e.lua\n"})
check(rc == 0 and out[KT] == "# marks\n1 a.lua\n7 b.lua\n2 c.lua\n3 d.lua\n9 e.lua\n", "keeps.txt: every file, the higher count")
rc, out = run({"plugins/gzreader.koplugin/main.lua": "<<<<<<< HEAD\na\n=======\nb\n>>>>>>> x\n"})
check(rc == 1 and "<<<<<<<" in out["plugins/gzreader.koplugin/main.lua"], "any other file: not settled (the PR is left out), left as it was")
rc, out = run({CL: "<<<<<<< HEAD\na\n=======\nb\n>>>>>>> x\n", "frontend/x.lua": "<<<<<<< HEAD\na\n=======\nb\n>>>>>>> x\n"})
check(rc == 1, "a changelog clash with another file's: not settled")
print("%d passed, %d failed" % (passed, failed))
sys.exit(1 if failed else 0)
