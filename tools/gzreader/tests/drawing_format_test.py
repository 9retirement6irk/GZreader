#!/usr/bin/env python3
"""Memos drawings made by gzreader_drawing.lua, checked the way memos reads them.

memos' drawing sheet (@usememos/canvas 26.11.2, src/png/chunks.ts
readSceneChunk and src/png/serialize.ts parseScene) opens a drawing when:
  * the file is a PNG whose chunks all have a good CRC up to the first IDAT;
  * a tEXt or zTXt chunk with the keyword "memos-canvas" comes before IDAT
    (zTXt: compression method 0, zlib data);
  * its text is JSON: type "memos-canvas", an integer version 1, a list of
    elements each with a non-empty string id, a string type, finite x and y,
    points for freedraw/line/arrow, text for text, fileId for image;
    files and appState objects when present.
This also checks what memos itself writes: the chunk right after IHDR,
ASCII-only text, coordinates with at most two decimals, a stroke's points as
offsets from its box's top left, and the file name. memos' own test drawing
(media/memos-v1.canvas.png) is checked first, so the checker is checked too.

  python3 drawing_format_test.py <dir with *.canvas.png from drawing_test.lua>
"""
import base64, json
import math
import os
import re
import struct
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
passed = failed = 0


def check(cond, msg):
    global passed, failed
    if cond:
        passed += 1
        print("  ok   " + msg)
    else:
        failed += 1
        print("  FAIL " + msg)


def chunks(png):
    if png[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not-png")
    at, out = 8, []
    while at < len(png):
        if at + 12 > len(png):
            raise ValueError("truncated")
        (n,) = struct.unpack(">I", png[at:at + 4])
        ctype, data = png[at + 4:at + 8], png[at + 8:at + 8 + n]
        if at + 12 + n > len(png):
            raise ValueError("truncated")
        (crc,) = struct.unpack(">I", png[at + 8 + n:at + 12 + n])
        out.append((ctype.decode("latin-1"), data, crc == (zlib.crc32(ctype + data) & 0xFFFFFFFF)))
        at += 12 + n
    return out


def finite(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v)


def valid_element(el):
    if not isinstance(el, dict):
        return False
    if not isinstance(el.get("id"), str) or el["id"] == "" or not isinstance(el.get("type"), str):
        return False
    if not finite(el.get("x")) or not finite(el.get("y")):
        return False
    if el["type"] in ("freedraw", "line", "arrow") and not isinstance(el.get("points"), list):
        return False
    if el["type"] == "text" and not isinstance(el.get("text"), str):
        return False
    if el["type"] == "image" and not isinstance(el.get("fileId"), str):
        return False
    return True


def read_scene(png):
    """memos' readSceneChunk + parseScene: (scene, None) or (None, reason), plus the chunk list."""
    try:
        cs = chunks(png)
    except ValueError as e:
        return None, str(e), []
    for ctype, data, crc_ok in cs:
        if ctype in ("IDAT", "IEND"):
            break
        if ctype not in ("tEXt", "zTXt") or not data.startswith(b"memos-canvas\x00"):
            continue
        if not crc_ok:
            return None, "bad-crc", cs
        body = data[len(b"memos-canvas\x00"):]
        if ctype == "zTXt":
            if body[:1] != b"\x00":
                return None, "bad-compression", cs
            try:
                body = zlib.decompress(body[1:])
            except zlib.error:
                return None, "bad-compression", cs
        text = body.decode("latin-1")
        try:
            data_ = json.loads(text)
        except ValueError:
            return None, "not-json", cs
        if not isinstance(data_, dict):
            return None, "invalid-scene", cs
        if data_.get("type") != "memos-canvas":
            return None, "wrong-type", cs
        v = data_.get("version")
        if not isinstance(v, int) or isinstance(v, bool) or v < 1:
            return None, "invalid-scene", cs
        if v > 1:
            return None, "version-too-high", cs
        els = data_.get("elements")
        if not isinstance(els, list) or not all(valid_element(e) for e in els):
            return None, "invalid-scene", cs
        if "files" in data_ and not isinstance(data_["files"], dict):
            return None, "invalid-scene", cs
        if "appState" in data_ and not isinstance(data_["appState"], dict):
            return None, "invalid-scene", cs
        return (data_, text), None, cs
    return None, "no-chunk", cs


def two_decimals(v):
    return isinstance(v, int) or abs(round(v, 2) - v) < 1e-9


def check_file(path, ours=True, strokes=None):
    name = os.path.basename(path)
    png = open(path, "rb").read()
    got, why, cs = read_scene(png)
    check(got is not None, f"{name}: memos opens it ({why or 'ok'})")
    if got is None:
        return None
    scene, text = got
    check(all(ok for _t, _d, ok in cs), f"{name}: every chunk's CRC is right")
    types = [t for t, _d, _ok in cs]
    check(types[0] == "IHDR" and types[1] in ("zTXt", "tEXt"), f"{name}: the scene chunk right after IHDR, as memos writes it")
    check(types[-1] == "IEND" and "IDAT" in types, f"{name}: still a whole PNG (IDAT, IEND)")
    w, h, depth, colour = struct.unpack(">IIBB", cs[0][1][:10])
    pixels = zlib.decompress(b"".join(d for t, d, _ok in cs if t == "IDAT"))
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}.get(colour, 1)
    row = (w * channels * depth + 7) // 8  # (a palette or grey PNG can pack several pixels in a byte)
    check(len(pixels) == h * (1 + row), f"{name}: its pixels decode ({w}x{h})")
    if strokes is None:
        strokes = ours
    if ours:
        check(re.fullmatch(r"drawing-\d{8}-\d{6}\.canvas\.png", name) is not None, f"{name}: named as memos names a drawing")
    check(all(ord(c) < 0x7F for c in text), f"{name}: the scene's text is ASCII (\\uXXXX above U+007E)")
    if not strokes:
        return scene
    for el in scene["elements"]:
        for key in ("x", "y", "width", "height"):
            if key in el:
                check(two_decimals(el[key]), f"{name}: {el['id']}.{key} has at most 2 decimals")
        if el["type"] == "freedraw":
            pts = el["points"]
            check(len(pts) > 0 and all(isinstance(p, list) and len(p) == 3 and all(finite(n) for n in p) for p in pts),
                  f"{name}: {el['id']}'s points are [dx, dy, pressure]")
            check(min(p[0] for p in pts) == 0 and min(p[1] for p in pts) == 0,
                  f"{name}: {el['id']}'s points start at its box's top left")
            check(abs(max(p[0] for p in pts) - el["width"]) < 0.011 and abs(max(p[1] for p in pts) - el["height"]) < 0.011,
                  f"{name}: {el['id']}'s width and height are its points' extent")
            check(all(0 <= p[2] <= 1 for p in pts), f"{name}: {el['id']}'s pressures between 0 and 1")
            check(el.get("strokeWidth") in (1, 2, 4) and isinstance(el.get("simulatePressure"), bool),
                  f"{name}: {el['id']}: a memos pen width, simulatePressure set")
            check(re.fullmatch(r"#[0-9a-f]{6}", el.get("strokeColor", "")) is not None, f"{name}: {el['id']}: colour #rrggbb")
        for key in ("groupIds", "boundElements"):
            check(isinstance(el.get(key), list), f"{name}: {el['id']}.{key} is a list")
    return scene


def check_background(scene, what):
    """A background as memos' drawing editor makes one (insertImage with background): an
    image element at (0, 0), locked, first; its file a PNG or JPEG data URL of that size."""
    els = (scene or {}).get("elements", [])
    check(len(els) >= 1 and els[0]["type"] == "image", f"{what}: the picture is the first element (under everything)")
    if not els or els[0]["type"] != "image":
        return
    bg = els[0]
    check(bg["x"] == 0 and bg["y"] == 0 and bg.get("locked") is True and bg.get("scale") == [1, 1],
          f"{what}: at (0, 0), locked, scale [1, 1]")
    f = scene.get("files", {}).get(bg["fileId"])
    check(isinstance(f, dict) and f.get("mimeType") in ("image/png", "image/jpeg") and isinstance(f.get("created"), (int, float))
          and f.get("dataURL", "").startswith("data:" + f.get("mimeType", "") + ";base64,"),
          f"{what}: its file: mimeType, a data URL of that type, created (memos' rules for files)")
    data = base64.b64decode(f["dataURL"].split(",", 1)[1])
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        w, h = struct.unpack(">II", data[16:24])
        check((w, h) == (bg["width"], bg["height"]) and max(w, h) <= 1440,
              f"{what}: the element as big as its picture ({w} x {h}), at most 1440 px (memos' stored size)")


def main():
    out = sys.argv[1]
    print("== memos' own test drawing (the checker, checked)")
    fixture = check_file(os.path.join(HERE, "media", "memos-v1.canvas.png"), ours=False)
    check(fixture is not None and fixture["appState"].get("futureState") == "kept", "memos' drawing: its scene as written by memos")
    bad = open(os.path.join(HERE, "media", "memos-v1.canvas.png"), "rb").read()
    i = bad.index(b"zTXt") + 20
    check(read_scene(bad[:i] + bytes([bad[i] ^ 1]) + bad[i + 1:])[1] == "bad-crc", "a damaged chunk: bad-crc, as memos says")

    print("== a drawing made in memos' web app: its strokes follow the same rules")
    real = check_file(os.path.join(HERE, "media", "memos-drawing.canvas.png"), ours=False, strokes=True)
    check(real is not None and sorted(e["type"] for e in real["elements"]).count("freedraw") == 6, "memos' drawing: 6 strokes")

    print("== drawings from gzreader_drawing.lua")
    files = sorted(f for f in os.listdir(out) if f.endswith(".canvas.png"))
    check(len(files) == 6, f"drawing_test.lua left 6 drawings ({len(files)})")
    scenes = {f: check_file(os.path.join(out, f)) for f in files}
    s0 = scenes.get("drawing-20261111-201500.canvas.png")
    check(s0 is not None and [e["type"] for e in s0["elements"]] == ["freedraw", "freedraw"], "the two strokes, in order")
    s1 = scenes.get("drawing-20261111-201501.canvas.png")
    check(s1 is not None and [t for t, _d, _ok in chunks(open(os.path.join(out, "drawing-20261111-201501.canvas.png"), "rb").read())][1] == "tEXt",
          "the drawing written without zlib has a tEXt chunk (memos reads those too)")
    s2 = scenes.get("drawing-20261111-201502.canvas.png")
    texts = [e.get("text") for e in (s2 or {}).get("elements", []) if e["type"] == "text"]
    check(texts == ["naïve \U0001F4DD"], "non-ASCII text comes back exactly (accent, emoji)")
    check(s2 is not None and s2["appState"]["viewBackgroundColor"] == "#f7f3e8", "the paper colour")
    s3 = scenes.get("drawing-20261111-201503.canvas.png")
    check(s3 is not None and s3["appState"].get("futureState") == "kept" and len(s3["elements"]) == 1,
          "memos' drawing with a stroke added: memos' unknown field kept")
    s4 = scenes.get("drawing-20261112-221000.canvas.png")
    check_background(s4, "a page on College ruled")

    print("== a drawing made in memos over a picture (the owner's, on College ruled paper)")
    mine = check_file(os.path.join(HERE, "media", "memos-paper.canvas.png"), ours=False, strokes=True)
    pics = [e for e in (mine or {}).get("elements", []) if e["type"] == "image"]
    check(len(pics) == 1 and pics[0]["fileId"] in mine["files"]
          and mine["files"][pics[0]["fileId"]]["dataURL"].startswith("data:image/jpeg;base64,"),
          "memos keeps the picture in the scene's files as a data URL")
    print(f"drawing format: {passed} passed, {failed} failed")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
