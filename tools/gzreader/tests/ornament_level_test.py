#!/usr/bin/env python3
"""The shelf ornaments stand level: an ornament with a flat base (feet, a
plinth, a foot ring) has its lowest points at the left and at the right at
the same height, so it sits flush on the plank instead of leaning on one
corner. Checks the grey pictures and their colour twins. Standard library
only (PNG decoded here with zlib)."""
import os
import struct
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
SHELF = os.path.join(HERE, "..", "..", "..", "plugins", "gzreader.koplugin", "icons", "shelf")

# Ornaments resting on a flat base. Plants (leaves hang below the pot's
# rim), the cats, the jug (its handle) and the Christmas tree have no single
# base line to measure, so they're left out.
FLAT = [
    "alarm-clock-01", "mantel-clock-01", "lambis-shell", "pumpkin", "horse-statue-01",
    "dutch-ship-medium", "antique-ceramic-vase-01", "brass-vase-01", "lantern-01",
    "marble-bust-01", "wooden-candlestick",
]
# Largest difference allowed between the left and right quarter's lowest
# points, as a share of the picture's height (before levelling: the mantel
# clock 0.147, the seashell 0.081, the alarm clock 0.037).
TOLERANCE = 0.035

failures = 0
passed = 0


def check(ok, what):
    global failures, passed
    if ok:
        passed += 1
    else:
        failures += 1
        print("FAIL: " + what)


def alpha_rows(path):
    with open(path, "rb") as f:
        data = f.read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", path
    pos, idat = 8, b""
    width = height = depth = ctype = interlace = None
    while pos < len(data):
        n, kind = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + n]
        if kind == b"IHDR":
            width, height, depth, ctype, _c, _f, interlace = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat += body
        pos += 12 + n
    channels = {4: 2, 6: 4}.get(ctype)
    assert channels and depth == 8 and interlace == 0, "%s: 8-bit grey+alpha or RGBA, not interlaced" % path
    raw = zlib.decompress(idat)
    stride = width * channels
    prev = bytearray(stride)
    rows = []
    for y in range(height):
        start = y * (stride + 1)
        kind = raw[start]
        line = bytearray(raw[start + 1:start + 1 + stride])
        for i in range(stride):
            a = line[i - channels] if i >= channels else 0
            b = prev[i]
            c = prev[i - channels] if i >= channels else 0
            if kind == 1:
                line[i] = (line[i] + a) & 255
            elif kind == 2:
                line[i] = (line[i] + b) & 255
            elif kind == 3:
                line[i] = (line[i] + (a + b) // 2) & 255
            elif kind == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                line[i] = (line[i] + pred) & 255
        rows.append(line[channels - 1::channels])
        prev = line
    return width, height, rows


def tilt(path):
    width, height, rows = alpha_rows(path)
    bottoms = []
    for x in range(width):
        low = None
        for y in range(height - 1, -1, -1):
            if rows[y][x] > 128:
                low = y
                break
        if low is not None:
            bottoms.append(low)
    q = max(1, len(bottoms) // 4)
    return (max(bottoms[:q]) - max(bottoms[-q:])) / height


for name in FLAT:
    for sub in ("", "colour"):
        path = os.path.join(SHELF, sub, "ornament-photo-%s.png" % name)
        t = tilt(path)
        check(abs(t) <= TOLERANCE, "%s%s stands level (left and right differ by %.3f of its height)" % (sub + "/" if sub else "", name, t))

print("ornaments level: %d passed, %d failed" % (passed, failures))
sys.exit(1 if failures else 0)
