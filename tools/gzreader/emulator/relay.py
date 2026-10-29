#!/usr/bin/env python3
"""Relay between the live emulator (live.lua) and the remote-control page.

  relay.py ingest <dir>   commands the page stored (an ArtifactData list saved
                          with out_dir) -> the emulator's cmd/ folder; prints
                          the documents to delete (they may hold typed text)
  relay.py screen [secs]  wait until the commands are done and the panel has
                          settled, then write screen_doc.json for the page

Typed text is never printed or logged here, only its length.
"""
import base64, glob, io, json, os, sys, time

OUT = os.environ.get("GZ_EMU_OUT", "/root/work/emu/live")
TREE = os.environ.get("GZ_EMU_TREE", "/root/work/emu/koreader")
STATE = os.path.join(OUT, "relay_state.json")


def load_state():
    try:
        with open(STATE) as f:
            return json.load(f)
    except Exception:
        return {"last_ts": 0, "sent_seq": -1, "n": 0}


def save_state(st):
    with open(STATE + ".tmp", "w") as f:
        json.dump(st, f)
    os.replace(STATE + ".tmp", STATE)


def docs_in(d):
    out = []
    for p in glob.glob(os.path.join(d, "**", "*.json"), recursive=True):
        try:
            with open(p) as f:
                doc = json.load(f)
        except Exception:
            continue
        data = doc.get("data", doc) if isinstance(doc, dict) else {}
        out.append({"id": doc.get("id") or doc.get("doc_id") or os.path.splitext(os.path.basename(p))[0],
                    "version": doc.get("version") or 1, "data": data if isinstance(data, dict) else {}})
    return out


ALLOWED = {"Up", "Down", "Left", "Right", "Press", "Back", "Menu", "Home", "LPgFwd", "LPgBack", "RPgFwd",
           "RPgBack", "Del", "AA", "Sym", "Space", "Shift", "Alt", "Period", "Enter"}
ALLOWED |= {chr(c) for c in range(ord("A"), ord("Z") + 1)}


def ingest(d):
    st = load_state()
    docs = sorted(docs_in(d), key=lambda x: (x["data"].get("ts") or 0, x["id"]))
    os.makedirs(os.path.join(OUT, "cmd"), exist_ok=True)
    lines, summary, deletes = [], [], []
    for doc in docs:
        data = doc["data"]
        ts = data.get("ts") or 0
        if doc.get("version"):
            deletes.append({"op": "delete", "collection": "cmds", "doc_id": doc["id"], "if_version": doc["version"]})
        if ts <= st["last_ts"]:
            continue
        st["last_ts"] = max(st["last_ts"], ts)
        kind, value = data.get("kind"), data.get("value")
        if kind == "key" and value in ALLOWED:
            lines.append("key " + value)
            summary.append(value)
        elif kind == "type" and isinstance(value, str) and value:
            lines.append("type " + value.replace("\n", " ")[:500])
            summary.append("type(%d chars)" % len(value))
        elif kind == "note" and isinstance(value, str):
            summary.append("NOTE: " + value[:500])
    if lines:
        st["n"] += 1
        name = os.path.join(OUT, "cmd", "%012d-%04d.txt" % (int(time.time() * 1000) % 10**12, st["n"]))
        with open(name + ".tmp", "w") as f:
            f.write("\n".join(lines) + "\n")
        os.replace(name + ".tmp", name)
    save_state(st)
    print(json.dumps({"sent": summary, "delete": deletes}))


def tail(path, n):
    try:
        with open(path, errors="replace") as f:
            return [l.rstrip("\n") for l in f.readlines()[-n:]]
    except Exception:
        return []


def screen(wait):
    st = load_state()
    deadline = time.time() + wait
    last_seq, stable_since = None, time.time()
    while time.time() < deadline:
        pending = glob.glob(os.path.join(OUT, "cmd", "*.txt"))
        try:
            with open(os.path.join(OUT, "state.json")) as f:
                s = json.load(f)
        except Exception:
            s = {}
        seq = s.get("seq")
        if seq != last_seq:
            last_seq, stable_since = seq, time.time()
        if not pending and time.time() - stable_since > 1.0:
            break
        time.sleep(0.25)
    try:
        with open(os.path.join(OUT, "state.json")) as f:
            s = json.load(f)
    except Exception:
        s = {"seq": -1, "windows": ""}
    alive = os.path.exists(os.path.join(OUT, "emu.pid")) and os.path.exists(
        "/proc/" + open(os.path.join(OUT, "emu.pid")).read().strip())
    if s.get("seq") == st["sent_seq"] and alive:
        print(json.dumps({"changed": False, "seq": s.get("seq"), "windows": s.get("windows")}))
        return
    from PIL import Image
    im = Image.open(os.path.join(OUT, "screen.png")).convert("L")
    im = im.quantize(colors=16, dither=Image.Dither.NONE) if hasattr(Image, "Dither") else im.quantize(16)
    buf = io.BytesIO()
    im.save(buf, "PNG", optimize=True)
    png = "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()
    log = [l for l in tail(os.path.join(TREE, "gzreader.log"), 14)]
    doc = {"png": png, "seq": s.get("seq"), "windows": s.get("windows", ""), "last_ts": st["last_ts"],
           "updated": int(time.time() * 1000), "status": "running" if alive else "stopped", "log": log}
    with open(os.path.join(OUT, "screen_doc.json"), "w") as f:
        json.dump(doc, f)
    st["sent_seq"] = s.get("seq")
    save_state(st)
    print(json.dumps({"changed": True, "seq": s.get("seq"), "kb": len(png) // 1024, "windows": s.get("windows"),
                      "status": doc["status"]}))


if __name__ == "__main__":
    if sys.argv[1] == "ingest":
        ingest(sys.argv[2])
    elif sys.argv[1] == "screen":
        screen(float(sys.argv[2]) if len(sys.argv) > 2 else 12)
