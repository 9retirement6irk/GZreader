"""A small Immich server for the tests (gzreader_immich.lua, the setup page, the sync page).

Mirrors the parts of Immich's API (v1.1xx to 3.x, under /api) GZreader uses:
  GET  /api/users/me
  GET  /api/albums                 ?shared=true: the albums shared with you
  GET  /api/albums/<id>            with its assets only with --old (Immich up to 2.x)
  POST /api/search/metadata        {albumIds, type, size, page} -> {assets: {items, nextPage}}
                                   (404 with --old: a server without album search)
  GET  /api/assets/<id>/thumbnail  ?size=preview: a PNG picture (Immich's are JPEG or WebP)
Sign-in: "x-api-key: <key>". KEY reads everything; LIMITED_KEY has no
album.read (403), as an API key made with too few permissions.
CORS: only with --cors (Immich sends none; a proxy in front has to): the
Origin is let in, preflights answered.

  python3 -I mock_immich.py PORT [--cors] [--old]

Test helpers: GET /__state (requests seen, without keys), POST /__reset.
"""
import json, struct, sys, threading, zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

KEY = "immich-test-key"
LIMITED_KEY = "immich-limited-key"
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 0
CORS = "--cors" in sys.argv
OLD = "--old" in sys.argv

LOCK = threading.Lock()
STATE = {"log": []}


def uid(n, kind="a"):
    # (a UUID made from a number: 'a' for assets, 'b' for albums)
    return "%08x-0000-4000-8000-%s%011x" % (n, kind, n)


def png(w, h, shade):
    """A grey test picture (a frame and stripes in a shade of its own), as a PNG."""
    rows = bytearray()
    for y in range(h):
        rows.append(0)
        for x in range(w):
            edge = x < 3 or y < 3 or x >= w - 3 or y >= h - 3
            rows.append(0 if edge else (shade if (x // 16) % 2 else 255 - shade))
    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 0, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(bytes(rows))) + chunk(b"IEND", b""))


# albums: "Kindle" (30 photos), "Trip" (3 photos and a video), "Family" (shared with you, 2 photos)
ALBUMS = [
    {"id": uid(1, "b"), "albumName": "Kindle", "assets": [{"id": uid(i), "type": "IMAGE"} for i in range(1, 31)]},
    {"id": uid(2, "b"), "albumName": "Trip", "assets": [{"id": uid(i), "type": "IMAGE"} for i in range(101, 104)]
        + [{"id": uid(199), "type": "VIDEO"}]},
]
SHARED = [
    {"id": uid(3, "b"), "albumName": "Family", "assets": [{"id": uid(i), "type": "IMAGE"} for i in range(201, 203)]},
]
ASSETS = {}
for a in ALBUMS + SHARED:
    for x in a["assets"]:
        ASSETS[x["id"]] = x


def summary(a):
    out = {"id": a["id"], "albumName": a["albumName"], "assetCount": len(a["assets"]), "shared": a in SHARED,
           "albumThumbnailAssetId": a["assets"][0]["id"], "description": ""}
    if OLD:
        out["assets"] = []
    return out


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"

    def end_headers(self):
        o = self.headers.get("Origin")
        if CORS and o:
            self.send_header("Access-Control-Allow-Origin", o)
        super().end_headers()

    def do_OPTIONS(self):
        if not CORS:
            return self.send(404, {"message": "Cannot OPTIONS"})
        self.send_response(204)
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", self.headers.get("Access-Control-Request-Headers") or "")
        self.send_header("Content-Length", "0")
        self.end_headers()

    def log_message(self, *a):
        pass

    def send(self, code, obj=None, ctype="application/json", raw=None):
        body = raw if raw is not None else (json.dumps(obj).encode() if obj is not None else b"")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def note(self, method, path, body=None):
        with LOCK:
            STATE["log"].append({"method": method, "path": path, "body": body,
                                 "key": "ok" if self.headers.get("x-api-key") == KEY else ("limited" if self.headers.get("x-api-key") == LIMITED_KEY else "none")})

    def auth(self):
        k = self.headers.get("x-api-key")
        if k in (KEY, LIMITED_KEY):
            return k
        self.send(401, {"message": "Invalid API key", "statusCode": 401})
        return None

    def do_GET(self):
        u = urlparse(self.path)
        q = parse_qs(u.query)
        if u.path == "/__state":
            with LOCK:
                return self.send(200, STATE)
        self.note("GET", self.path)
        k = self.auth()
        if not k:
            return
        if u.path == "/api/users/me":
            if k == LIMITED_KEY:
                return self.send(403, {"message": "Missing required permission: user.read"})
            return self.send(200, {"id": "u1", "name": "Will", "email": "will@example.com"})
        if u.path == "/api/albums":
            if k == LIMITED_KEY:
                return self.send(403, {"message": "Missing required permission: album.read"})
            shared = q.get("shared", [""])[0] == "true"
            return self.send(200, [summary(a) for a in (SHARED if shared else ALBUMS)])
        if u.path.startswith("/api/albums/"):
            aid = u.path.rsplit("/", 1)[1]
            for a in ALBUMS + SHARED:
                if a["id"] == aid:
                    out = summary(a)
                    if OLD:
                        out["assets"] = a["assets"]
                    return self.send(200, out)
            return self.send(400, {"message": "Not found or no album.read access"})
        if u.path.startswith("/api/assets/") and u.path.endswith("/thumbnail"):
            aid = u.path.split("/")[3]
            if aid not in ASSETS:
                return self.send(400, {"message": "Not found or no asset.view access"})
            n = int(aid[:8], 16)
            # (a landscape preview, bigger than a Kindle's screen: made to fit there)
            return self.send(200, ctype="image/png", raw=png(320 + n % 7, 200 + n % 5, 40 + (n * 37) % 160))
        return self.send(404, {"message": "Cannot GET " + u.path})

    def do_POST(self):
        u = urlparse(self.path)
        n = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(n) if n else b""
        if u.path == "/__reset":
            with LOCK:
                STATE["log"] = []
            return self.send(200, {})
        try:
            body = json.loads(raw.decode() or "{}")
        except ValueError:
            body = None
        self.note("POST", u.path, body)
        if not self.auth():
            return
        if u.path == "/api/search/metadata":
            if OLD:
                return self.send(404, {"message": "Cannot POST /api/search/metadata"})
            if not isinstance(body, dict) or not isinstance(body.get("albumIds"), list):
                return self.send(400, {"message": ["albumIds must be an array"]})
            size = int(body.get("size") or 250)
            page = int(body.get("page") or 1)
            items = []
            for a in ALBUMS + SHARED:
                if a["id"] in body["albumIds"]:
                    items += [x for x in a["assets"] if not body.get("type") or x["type"] == body["type"]]
            chunk = items[(page - 1) * size: page * size]
            more = str(page + 1) if page * size < len(items) else None
            return self.send(200, {"albums": {"total": 0, "count": 0, "items": [], "facets": []},
                                   "assets": {"total": len(items), "count": len(chunk), "items": chunk, "facets": [], "nextPage": more}})
        return self.send(404, {"message": "Cannot POST " + u.path})


ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
