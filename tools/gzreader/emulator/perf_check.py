#!/usr/bin/env python3
"""Compare an emulator perf run (perf.lua's perf.json) with the baseline.

Each phase's CPU time is divided by the run's calibration (a fixed piece of
Lua timed on the same machine), so a slower or faster CI machine doesn't
look like a change in GZreader. A phase that costs more than the baseline by
WARN (25%) is flagged; by FAIL (50%), the check fails. Phases under
MIN_CPU s are only shown (too short to time reliably).

  perf_check.py <perf.json> <perf_baseline.json>         markdown for summary.md; exit 1 on a FAIL
  perf_check.py --update <perf.json> <perf_baseline.json> record this run as the model's baseline

No baseline for the model yet: the numbers are shown, nothing fails.
"""
import json, sys

WARN, FAIL, MIN_CPU = 1.25, 1.50, 0.3


def load(path, default=None):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def compare(run, base):
    """(lines of markdown, failed?) for one run against its model's baseline (or None)."""
    model = run.get("model", "?")
    cal = float(run.get("calibration") or 0)
    lines, failed = [], False
    if cal <= 0:
        return [f"- ❌ {model} perf: no calibration in the run"], True
    head = f"- {model} perf (CPU s; calibration {cal:.3f} s"
    if base:
        head += f", baseline {float(base['calibration']):.3f} s)"
    else:
        head += "): no baseline yet, nothing compared. To record this run: `perf_check.py --update`"
    lines.append(head)
    order = run.get("order") or sorted(run.get("phases", {}))
    for name in order:
        ph = run["phases"].get(name) or {}
        c = float(ph.get("cpu") or 0)
        b = (base or {}).get("phases", {}).get(name)
        if not b:
            lines.append(f"  - {name}: {c:.2f} s")
            continue
        bc = float(b.get("cpu") or 0)
        ratio = (c / cal) / (bc / float(base["calibration"])) if bc > 0 else 1.0
        pct = (ratio - 1) * 100
        mark = "✅"
        if max(c, bc) >= MIN_CPU and ratio >= FAIL:
            mark, failed = "❌", True
        elif max(c, bc) >= MIN_CPU and ratio >= WARN:
            mark = "⚠️"
        lines.append(f"  - {mark} {name}: {c:.2f} s, {pct:+.0f}% against the baseline ({bc:.2f} s)")
    if run.get("lua_mb") is not None:
        lines.append(f"  - Lua memory {float(run['lua_mb']):.1f} MB, modules loaded {run.get('modules', '?')}")
    return lines, failed


def main(argv):
    update = "--update" in argv
    args = [a for a in argv if a != "--update"]
    if len(args) != 2:
        print(__doc__)
        return 2
    run = load(args[0])
    if not isinstance(run, dict) or not isinstance(run.get("phases"), dict):
        print("- ❌ perf: no perf.json (the emulator run didn't finish)")
        return 1
    baseline = load(args[1], {}) or {}
    model = run.get("model", "?")
    if update:
        baseline[model] = {"calibration": run["calibration"],
                           "phases": {k: {"cpu": round(float(v.get("cpu", 0)), 3)} for k, v in run["phases"].items()}}
        with open(args[1], "w") as f:
            json.dump(baseline, f, indent=1, sort_keys=True)
            f.write("\n")
        print(f"baseline for {model} recorded")
        return 0
    lines, failed = compare(run, baseline.get(model))
    print("\n".join(lines))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
