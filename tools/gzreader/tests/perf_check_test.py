#!/usr/bin/env python3
"""tools/gzreader/emulator/perf_check.py: CI's CPU budgets for the emulator perf run."""
import json, os, subprocess, sys, tempfile

sys.dont_write_bytecode = True  # (no __pycache__ next to perf_check.py)

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "..", "emulator", "perf_check.py")
sys.path.insert(0, os.path.dirname(TOOL))
import perf_check  # noqa: E402

passed = failed = 0


def check(cond, what):
    global passed, failed
    if cond:
        passed += 1
        print("  ok   " + what)
    else:
        failed += 1
        print("  FAIL " + what)


def run_of(cal, **phases):
    return {"model": "k3", "calibration": cal, "order": list(phases),
            "phases": {k: {"cpu": v, "wall": v * 2} for k, v in phases.items()}, "lua_mb": 14.2, "modules": 900}


base = {"calibration": 0.5, "phases": {"open a book": {"cpu": 4.0}, "20 page turns": {"cpu": 6.0}, "startup": {"cpu": 0.2}}}

lines, bad = perf_check.compare(run_of(0.5, **{"open a book": 4.2, "20 page turns": 6.0}), base)
check(not bad and "✅ open a book: 4.20 s, +5%" in "\n".join(lines), "5% more: fine")

lines, bad = perf_check.compare(run_of(0.5, **{"open a book": 5.4}), base)
check(not bad and "⚠️ open a book" in "\n".join(lines), "35% more: flagged, not failed")

lines, bad = perf_check.compare(run_of(0.5, **{"20 page turns": 9.6}), base)
check(bad and "❌ 20 page turns: 9.60 s, +60%" in "\n".join(lines), "60% more: fails")

lines, bad = perf_check.compare(run_of(1.0, **{"20 page turns": 11.0}), base)
check(not bad and "-8%" in "\n".join(lines), "a machine twice as slow (calibration 1.0 s): compared as such, no failure")

lines, bad = perf_check.compare(run_of(0.5, startup=0.29), base)
check(not bad, "under 0.3 s of CPU: too short to judge (+45%, shown only)")

lines, bad = perf_check.compare(run_of(0.5, **{"new phase": 3.0}), base)
check(not bad and "new phase: 3.00 s" in "\n".join(lines), "a phase the baseline doesn't have: shown")

lines, bad = perf_check.compare(run_of(0.5, **{"open a book": 4.0}), None)
check(not bad and "no baseline yet" in lines[0], "no baseline for the model: shown, nothing fails")

lines, bad = perf_check.compare(run_of(0, **{"open a book": 4.0}), base)
check(bad, "no calibration: fails (the run is broken)")

with tempfile.TemporaryDirectory() as d:
    rp, bp = os.path.join(d, "perf.json"), os.path.join(d, "base.json")
    with open(rp, "w") as f:
        json.dump(run_of(0.5, **{"open a book": 9.0}), f)
    with open(bp, "w") as f:
        json.dump({"k3": base, "pw3": {"calibration": 1, "phases": {}}}, f)
    r = subprocess.run([sys.executable, TOOL, rp, bp], capture_output=True, text=True)
    check(r.returncode == 1 and "❌ open a book" in r.stdout, "command line: exit 1 on a failure")
    r = subprocess.run([sys.executable, TOOL, "--update", rp, bp], capture_output=True, text=True)
    saved = json.load(open(bp))
    check(r.returncode == 0 and saved["k3"]["phases"]["open a book"]["cpu"] == 9.0 and "pw3" in saved,
          "--update: this model's baseline replaced, the others kept")
    r = subprocess.run([sys.executable, TOOL, os.path.join(d, "missing.json"), bp], capture_output=True, text=True)
    check(r.returncode == 1 and "didn't finish" in r.stdout, "no perf.json: fails, says so")

with open(os.path.join(HERE, "..", "emulator", "perf_baseline.json")) as f:
    check(isinstance(json.load(f), dict), "perf_baseline.json is valid JSON")

print(f"\n{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
