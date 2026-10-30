"""A small Memos v0.31 server for the Notes tab's tests and the emulator.

Mirrors the parts of Memos' REST API (v0.31.0, /api/v1) GZreader uses:
  GET   /api/v1/auth/me
  GET   /api/v1/memos            pageSize, pageToken, orderBy, filter (CEL subset)
  POST  /api/v1/memos            {content, visibility}
  PATCH /api/v1/memos/<id>       ?updateMask=content,visibility,pinned
  GET   /file/attachments/<uid>/<filename>
Sign-in: "Authorization: Bearer <token>" (TOKEN below).

  python3 -I mock_memos.py PORT [--sample] [--prefix /api]

--sample fills it with a few notes (with a picture and a PDF), as in the
mockup. --prefix /api serves the newer layout (no /api/v1) instead.
Test helpers: GET /__state (all notes), POST /__reset, POST /__offline?on=1.
"""
import json, re, sys, time, threading, zlib, struct
from datetime import datetime, timezone, timedelta
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

TOKEN = "memos-test-token"
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 0
SAMPLE = "--sample" in sys.argv
PREFIX = "/api/v1"
if "--prefix" in sys.argv:
    PREFIX = sys.argv[sys.argv.index("--prefix") + 1]

LOCK = threading.Lock()
STATE = {"memos": [], "next": 1, "log": [], "offline": False, "files": {}}


def png(w, h):
    """A gray test picture (stripes and a frame), as a PNG."""
    rows = b""
    for y in range(h):
        row = bytearray([0])
        for x in range(w):
            edge = x < 4 or y < 4 or x >= w - 4 or y >= h - 4
            v = 0 if edge else (60 if (x // 20 + y // 20) % 2 else 200)
            row.append(v)
        rows += bytes(row)
    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 0, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))


def pdf():
    text = "BT /F1 24 Tf 72 720 Td (Trail map: Springer Mountain to Neels Gap) Tj ET"
    objs = [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
        "<< /Length %d >>\nstream\n%s\nendstream" % (len(text), text),
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ]
    out = "%PDF-1.4\n"
    offs = []
    for i, o in enumerate(objs, 1):
        offs.append(len(out))
        out += "%d 0 obj\n%s\nendobj\n" % (i, o)
    x = len(out)
    out += "xref\n0 %d\n0000000000 65535 f \n" % (len(objs) + 1)
    for o in offs:
        out += "%010d 00000 n \n" % o
    out += "trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objs) + 1, x)
    return out.encode()


def iso(dt):
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


TAG_RE = re.compile(r"(?:^|[\s(])#([\w\-/]+)")


def tags_of(content):
    seen = []
    for t in TAG_RE.findall(content or ""):
        if t not in seen:
            seen.append(t)
    return seen


def add(content, visibility="PRIVATE", pinned=False, ago=timedelta(0), place=None, attachments=None):
    with LOCK:
        n = STATE["next"]
        STATE["next"] += 1
    t = datetime.now(timezone.utc) - ago
    m = {
        "name": "memos/m%03d" % n, "state": "NORMAL", "creator": "users/1",
        "createTime": iso(t), "updateTime": iso(t), "displayTime": iso(t),
        "content": content, "visibility": visibility, "tags": tags_of(content), "pinned": pinned,
        "attachments": attachments or [], "relations": [], "reactions": [],
        "property": {"hasLink": False, "hasTaskList": "- [" in content, "hasCode": False, "hasIncompleteTasks": "- [ ]" in content},
        "snippet": content[:60],
    }
    if place:
        m["location"] = {"placeholder": place, "latitude": 34.56, "longitude": -84.25}
    STATE["memos"].append(m)
    return m


def attachment(uid, filename, typ, data):
    STATE["files"][uid] = data
    return {"name": "attachments/" + uid, "createTime": iso(datetime.now(timezone.utc)), "filename": filename,
            "content": "", "externalLink": "", "type": typ, "size": str(len(data)), "memo": ""}


def sample():
    add("Finish A Walk in the Woods before the trip. Bryson's chapter on the Smokies is the funniest so far. #reading",
        pinned=True, ago=timedelta(minutes=20))
    add("## Georgia section\n\nTrail plan for the Georgia section. Permit is booked. Map attached.\n\n"
        "- [x] permit\n- [ ] trail map printed\n- [ ] **bear bag**\n\n#travel #hiking",
        ago=timedelta(hours=7), place="Amicalola Falls",
        attachments=[attachment("trailmap", "Trail map.pdf", "application/pdf", pdf())])
    add("\"The woods were full of ghosts.\" Think about using this as the opening line. #quotes", ago=timedelta(days=1, hours=2))
    add("Notes tab for the Kindle: sticky notes, open with a letter key, filter by tag. #ideas #gzreader",
        ago=timedelta(days=3))
    add("- [ ] headlamp batteries\n- [x] water filter\n- [ ] wool socks\n\n#shopping", ago=timedelta(days=5), place="Home")
    pic = attachment("ridge", "ridge.png", "image/png", png(320, 200))
    add("The view from the ridge, for the sleep screen.\n\n![ridge](/file/attachments/ridge/ridge.png)\n\n#travel",
        ago=timedelta(days=8), place="Blood Mountain", attachments=[pic])
    add("Ask the library about the large-print edition. #reading", ago=timedelta(days=40))


# --- the CEL subset GZreader sends ------------------------------------------

def matcher(f):
    if not f:
        return lambda m: True
    tests = []
    for part in [p.strip() for p in f.split("&&")]:
        mm = re.fullmatch(r'"((?:[^"\\]|\\.)*)" in tags', part)
        if mm:
            tag = json.loads('"%s"' % mm.group(1))
            tests.append(lambda m, tag=tag: tag in m["tags"] or any(t.startswith(tag + "/") for t in m["tags"]))
            continue
        if part == "pinned == true" or part == "pinned":
            tests.append(lambda m: m["pinned"])
            continue
        mm = re.fullmatch(r'created_ts > now - duration\("(\d+)h"\)', part)
        if mm:
            since = datetime.now(timezone.utc) - timedelta(hours=int(mm.group(1)))
            tests.append(lambda m, since=since: datetime.strptime(m["createTime"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc) > since)
            continue
        mm = re.fullmatch(r'content\.contains\("((?:[^"\\]|\\.)*)"\)', part)
        if mm:
            needle = json.loads('"%s"' % mm.group(1))
            tests.append(lambda m, needle=needle: needle in m["content"])
            continue
        if part == "has_task_list":
            tests.append(lambda m: m["property"]["hasTaskList"])
            continue
        return None  # Memos answers 400 for filters it can't parse
    return lambda m: all(t(m) for t in tests)


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def send(self, code, obj=None, ctype="application/json", raw=None):
        body = raw if raw is not None else (json.dumps(obj).encode() if obj is not None else b"")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def authed(self):
        a = self.headers.get("Authorization", "")
        if a != "Bearer " + TOKEN:
            self.send(401, {"code": 16, "message": "Unauthenticated"})
            return False
        return True

    def body(self):
        n = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(n) if n else b""
        try:
            return json.loads(raw or b"{}")
        except ValueError:
            return {}

    def api(self, path):
        """The API path without the prefix, or None (404: other layout)."""
        if path.startswith(PREFIX + "/"):
            rest = path[len(PREFIX):]
            if PREFIX == "/api" and rest.startswith("/v1/"):
                return None
            return rest
        return None

    def note(self, u):
        STATE["log"].append(self.command + " " + u.path + ("?" + u.query if u.query else ""))
        if self.headers.get("Authorization"):
            assert TOKEN not in u.path and TOKEN not in u.query

    def do_GET(self):
        u = urlparse(self.path)
        self.note(u)
        if u.path == "/__state":
            return self.send(200, {"memos": STATE["memos"], "log": STATE["log"]})
        if STATE["offline"]:
            self.close_connection = True
            return
        if u.path.startswith("/file/attachments/"):
            if not self.authed():
                return
            parts = u.path.split("/")
            uid = parts[3] if len(parts) > 3 else ""
            data = STATE["files"].get(uid)
            if data is None:
                return self.send(404, {"message": "not found"})
            typ = "application/pdf" if data.startswith(b"%PDF") else "image/png"
            return self.send(200, ctype=typ, raw=data)
        p = self.api(u.path)
        if p is None:
            return self.send(404, raw=b"404 page not found", ctype="text/plain")
        if not self.authed():
            return
        q = {k: v[0] for k, v in parse_qs(u.query).items()}
        if p == "/auth/me":
            return self.send(200, {"user": {"name": "users/1", "username": "will", "displayName": "Will", "role": "HOST"}})
        if p == "/memos":
            ok = matcher(q.get("filter"))
            if ok is None:
                return self.send(400, {"code": 3, "message": "invalid filter"})
            items = [m for m in STATE["memos"] if m["state"] == "NORMAL" and ok(m)]
            items.sort(key=lambda m: (not m["pinned"], [-ord(c) for c in m["createTime"]]))
            size = int(q.get("pageSize") or 10)
            start = int(q.get("pageToken") or 0)
            page = items[start:start + size]
            nxt = str(start + size) if start + size < len(items) else ""
            return self.send(200, {"memos": page, "nextPageToken": nxt})
        return self.send(404, {"message": "not found"})

    def do_POST(self):
        u = urlparse(self.path)
        self.note(u)
        if u.path == "/__reset":
            STATE["memos"].clear(); STATE["log"].clear(); STATE["files"].clear(); STATE["next"] = 1
            if "sample=1" in u.query:
                sample()
            return self.send(200, {})
        if u.path == "/__offline":
            STATE["offline"] = "on=1" in u.query
            return self.send(200, {})
        if STATE["offline"]:
            self.close_connection = True
            return
        p = self.api(u.path)
        if p is None:
            return self.send(404, raw=b"404 page not found", ctype="text/plain")
        if not self.authed():
            return
        if p == "/memos":
            b = self.body()
            if not (b.get("content") or "").strip():
                return self.send(400, {"code": 3, "message": "content is required"})
            m = add(b["content"], visibility=b.get("visibility") or "PRIVATE")
            return self.send(200, m)
        return self.send(404, {"message": "not found"})

    def do_PATCH(self):
        u = urlparse(self.path)
        self.note(u)
        if STATE["offline"]:
            self.close_connection = True
            return
        p = self.api(u.path)
        if p is None:
            return self.send(404, raw=b"404 page not found", ctype="text/plain")
        if not self.authed():
            return
        mm = re.fullmatch(r"/(memos/[\w\-]+)", p)
        if not mm:
            return self.send(404, {"message": "not found"})
        m = next((x for x in STATE["memos"] if x["name"] == mm.group(1)), None)
        if not m:
            return self.send(404, {"code": 5, "message": "memo not found"})
        mask = parse_qs(u.query).get("updateMask", [""])[0]
        if not mask:
            return self.send(400, {"code": 3, "message": "update mask is required"})
        b = self.body()
        for field in mask.split(","):
            if field == "content":
                m["content"] = b.get("content", m["content"])
                m["tags"] = tags_of(m["content"])
                m["property"]["hasTaskList"] = "- [" in m["content"]
            elif field == "visibility":
                if b.get("visibility") not in ("PRIVATE", "PROTECTED", "PUBLIC"):
                    return self.send(400, {"code": 3, "message": "invalid visibility"})
                m["visibility"] = b["visibility"]
            elif field == "pinned":
                m["pinned"] = bool(b.get("pinned"))
            else:
                return self.send(400, {"code": 3, "message": "unsupported update mask: " + field})
        m["updateTime"] = iso(datetime.now(timezone.utc))
        return self.send(200, m)


if SAMPLE:
    sample()
srv = ThreadingHTTPServer(("127.0.0.1", PORT), H)
print("mock memos on", srv.server_address[1], flush=True)
srv.serve_forever()
