#!/usr/bin/env python3
"""Compare menu text sizes across models: menu_sizes.py <out dir>/<model>/sizes.json ..."""
import json, sys

rows = {}
screens = set()
for p in sys.argv[1:]:
    d = json.load(open(p))
    rows[d["model"]] = d
    screens.update(d["screens"].keys())
screens = sorted(screens)
print("model  dpi  " + "  ".join(f"{s[2:]:>13}" for s in screens))
for m, d in rows.items():
    cells = []
    for s in screens:
        v = d["screens"].get(s, {})
        cells.append(f"{v.get('mode_px') or '-':>4}px {v.get('mode_mm') or 0:4.1f}mm" if v.get("mode_px") else f"{'-':>13}")
    print(f"{m:5} {d['dpi']:4}  " + "  ".join(cells))
