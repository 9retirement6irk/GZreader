"""Mock BookOrbit server: the routes GZreader's BookOrbit backend uses.

A book's file is listed with role "primary" (the book's main file) or "content"
(another of its files), as a real server (v3.9.0, probed 2026-11-22) does; both
download.

Shapes and checks follow BookOrbit's source at commit e60ab43 (2026-11-21;
github.com/bookorbit/bookorbit: server/src/modules/koreader, .../audiobook,
packages/types/src/koreader.ts and audiobook.ts). Nothing of BookOrbit's code
is copied: this is a stand-in written from its routes and field names.

Two sign-ins, as the real server:
  * the KOReader API (/api/v1/koreader/...): headers x-auth-user and
    x-auth-key (the password, or its MD5 as KOSync clients send);
  * the main API (/api/v1/auth/me, /api/v1/audiobooks/...): an API key
    ("bok_" + 49 characters) as Authorization: Bearer or X-Api-Key.

    python3 -I mock_bookorbit.py <port>

Control routes for tests (no sign-in): GET /_mock/state, POST /_mock/set
(a JSON object merged into STATE's switches), POST /_mock/reset.
"""
import hashlib, json, re, sys, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs, quote

KO_USER, KO_PASSWORD = "will-kindle", "hunter22"
API_KEY = "bok_" + "a1B2c3D4e5" * 4 + "f6G7h8I9j"  # 53 characters
MD5 = re.compile(r"^[0-9a-f]{32}$", re.I)
DEVICE_ID = re.compile(r"^[A-Za-z0-9_-]{1,100}$")
DEVICE_TIME = re.compile(r"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$")
ASSET_ID = re.compile(r"^aud_[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$", re.I)
UUID = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$", re.I)
ISO = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$")
CAPABILITIES = ["catalogBulkManifest", "catalogDashboardSections", "bookmarkSync", "readAloudDeliveryVariants",
                "readAloudDeliverySettings", "catalogListsV2", "catalogPublishedSort", "sidecarState",
                "annotationPendingBooks", "catalogBooksQuery"]
SORTS = {"title", "author", "published", "recently_added", "recently_updated", "recently_read", "series"}

# The "book files": their bytes are what a download returns. fileHash here is the
# file's MD5 (the real server's is KOReader's partial MD5; the tests only need the
# two ends to agree).
def _png(w, h):
    """A plain cover: light grey with a dark edge (stdlib only)."""
    import struct, zlib
    rows = b"".join(b"\0" + bytes(60 if x < 3 or y < 3 or x >= w - 3 or y >= h - 3 else 205 for x in range(w)) for y in range(h))
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 0, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b"")


PNG = _png(120, 168)


def book(i, title, authors, library, series=None, idx=None, fmt="epub", collections=()):
    data = ("%s by %s\n" % (title, ", ".join(authors))).encode() * 40
    return {"id": i, "title": title, "authors": authors, "libraryId": library, "seriesName": series,
            "seriesId": (900 + sum(map(ord, series)) % 90) if series else None, "seriesIndex": idx,
            "format": fmt, "fileId": 5000 + i, "data": data, "hash": hashlib.md5(data).hexdigest(),
            "collections": list(collections), "addedAt": "2026-10-%02dT08:00:00.000Z" % (i % 27 + 1),
            "updatedAt": "2026-11-%02dT09:30:00.000Z" % (i % 20 + 1)}


LIBRARIES = {1: "Fiction", 2: "Non-fiction"}
COLLECTIONS = {11: "Beach reads", 12: "Book club"}
BOOKS = [
    book(101, "The Long Way Round", ["Ada Marsh"], 1, "Waymarks", 1, collections=[11]),
    book(102, "The Short Way Back", ["Ada Marsh"], 1, "Waymarks", 2),
    book(103, "A Field Guide to Fog", ["Ben Okafor"], 2, collections=[12]),
    book(104, "Night Trains", ["Clara Voss", "Ben Okafor"], 1, collections=[11, 12]),
    book(105, "Tide Tables", ["Dmitri Hale"], 2, fmt="pdf"),
]
AUDIOBOOK = {
    "id": 201, "title": "The Long Way Round", "authors": ["Ada Marsh"], "narrators": ["June Park"],
    "assets": [
        {"assetId": "aud_11111111-1111-4111-8111-111111111111", "fileId": 6201, "sequence": 0, "format": "mp3",
         "durationMs": 60000, "data": b"ID3" + b"\0" * 4000},
        {"assetId": "aud_22222222-2222-4222-8222-222222222222", "fileId": 6202, "sequence": 1, "format": "mp3",
         "durationMs": 45000, "data": b"ID3" + b"\1" * 3000},
    ],
}


def fresh():
    return {
        "capabilities": list(CAPABILITIES),
        "sync_enabled": True,     # the KOReader credentials' "sync enabled" switch
        "ko_permission": True,    # the account's KOReader sync permission
        "api_keys_enabled": True,
        "api_key_write": True,    # False: a read key (PUT answers 403 API_KEY_READ_ONLY)
        "offline": False,         # every route answers 503
        "progress": {},           # hash -> {percentage, progress, device, device_id, timestamp}
        "playback": {},           # book id -> state
        "seen": [],               # (method, path) of signed-in requests, newest last
        "devices": {},            # deviceId -> deviceModel
    }


STATE = fresh()


def manifest_revision():
    h = hashlib.sha256()
    for a in AUDIOBOOK["assets"]:
        h.update(a["assetId"].encode() + a["data"])
    return h.hexdigest()


def pct100(p):
    """KOReader sends 0-1; BookOrbit keeps and shows 0-100, to two places."""
    return round(p * 10000) / 100.0


def list_item(b):
    p = STATE["progress"].get(b["hash"])
    return {"id": b["id"], "title": b["title"], "authors": b["authors"], "seriesId": b["seriesId"],
            "seriesName": b["seriesName"], "seriesIndex": b["seriesIndex"],
            "progressPercentage": p and pct100(p["percentage"]), "lastReadAt": p and p["updatedAt"],
            "readStatus": p and "reading" or None, "formats": [b["format"]], "hasCover": True,
            "thumbnailUrl": "/api/v1/koreader/plugin/catalog/books/%d/thumbnail" % b["id"],
            "detailUrl": "/api/v1/koreader/plugin/catalog/books/%d" % b["id"],
            "addedAt": b["addedAt"], "updatedAt": b["updatedAt"]}


def detail(b):
    d = list_item(b)
    p = STATE["progress"].get(b["hash"])
    d.update({"subtitle": None, "description": "About %s." % b["title"], "publisher": "Example House",
              "publishedDate": "2020-05-01", "publishedYear": 2020, "language": "en", "isbn10": None, "isbn13": None,
              "libraryId": b["libraryId"], "libraryName": LIBRARIES[b["libraryId"]], "rating": None, "pageCount": 240,
              "collections": [{"id": c, "name": COLLECTIONS[c]} for c in b["collections"]], "genres": [], "tags": [],
              "progress": p and {"fileId": b["fileId"], "percentage": pct100(p["percentage"]),
                                 "koreaderProgress": p.get("progress"), "updatedAt": p["updatedAt"]} or None,
              "files": [{"id": b["fileId"], "format": b["format"], "role": "primary", "downloadVariant": "original",
                         "sizeBytes": len(b["data"]), "sourceSizeBytes": len(b["data"]), "durationSeconds": None, "fileHash": b["hash"],
                         "downloadUrl": "/api/v1/koreader/plugin/catalog/files/%d/download" % b["fileId"],
                         "devicePath": "%s/%s.%s" % (b["authors"][0], b["title"], b["format"])}],
              "relatedSections": []})
    return d


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    # ---------------------------------------------------------------- plumbing
    def send(self, code, body=None, ctype="application/json", headers=None):
        raw = body if isinstance(body, (bytes, bytearray)) else json.dumps(body if body is not None else {}).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(raw)))
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(raw)

    def error(self, code, message, error_code=None):
        body = {"statusCode": code, "message": message, "path": self.path.split("?")[0],
                "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime()), "requestId": "req-mock"}
        if error_code:
            body["errorCode"] = error_code
        self.send(code, body)

    def body(self):
        n = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(n) if n else b""
        try:
            return json.loads(raw) if raw else {}
        except ValueError:
            return None

    def ko_user(self):
        """The KOReader guard: x-auth-user + x-auth-key (the password or its MD5)."""
        user, key = self.headers.get("x-auth-user"), self.headers.get("x-auth-key")
        if not user or not key:
            return self.error(401, "Missing KOReader credentials")
        if user != KO_USER:
            return self.error(401, "Invalid credentials")
        if not STATE["sync_enabled"]:
            return self.error(403, "Sync is disabled")
        want = hashlib.md5(KO_PASSWORD.encode()).hexdigest()
        got = key.lower() if MD5.match(key) else hashlib.md5(key.encode()).hexdigest()
        if got != want:
            return self.error(401, "Invalid credentials")
        if not STATE["ko_permission"]:
            return self.error(401, "KOReader sync permission revoked")
        return user

    def api_key(self, write=False):
        """The main API's key: Bearer or X-Api-Key, never the query string."""
        auth = self.headers.get("Authorization")
        m = re.match(r"^Bearer\s+(\S+)\s*$", auth or "", re.I)
        bearer = m and m.group(1) or None
        header = (self.headers.get("X-Api-Key") or "").strip() or None
        if header and auth is not None and bearer != header:
            return self.error(401, "Conflicting credentials")
        key = header or (bearer if bearer and bearer.startswith("bok_") else None)
        if not key:
            return self.error(401, "Unauthorized")  # (a Bearer that isn't a key is taken for a session token)
        if len(key) != len(API_KEY):
            return self.error(401, "Invalid API key")  # malformed: the real key carries a checksum
        if not STATE["api_keys_enabled"]:
            return self.error(401, "API keys are turned off on this server", "API_KEYS_DISABLED")
        if key != API_KEY:
            return self.error(401, "Invalid API key")
        if write and not STATE["api_key_write"]:
            return self.error(403, "This API key is read-only", "API_KEY_READ_ONLY")
        return key

    def device(self, dto):
        """PluginDeviceDto: what every plugin POST carries."""
        if not isinstance(dto, dict):
            return self.error(400, "Bad JSON")
        if not isinstance(dto.get("deviceId"), str) or not DEVICE_ID.match(dto["deviceId"]):
            return self.error(400, "deviceId must match /^[A-Za-z0-9_-]{1,100}$/")
        if not isinstance(dto.get("deviceModel"), str) or len(dto["deviceModel"]) > 100:
            return self.error(400, "deviceModel must be a string of at most 100 characters")
        if not isinstance(dto.get("pluginVersion"), str) or len(dto["pluginVersion"]) > 20:
            return self.error(400, "pluginVersion must be a string of at most 20 characters")
        if "deviceTime" in dto and not (isinstance(dto["deviceTime"], str) and DEVICE_TIME.match(dto["deviceTime"])):
            return self.error(400, "deviceTime must be YYYY-MM-DD HH:MM:SS")
        STATE["devices"][dto["deviceId"]] = dto["deviceModel"]
        return True

    # ---------------------------------------------------------------- routes
    def do_GET(self):
        self.route("GET")

    def do_POST(self):
        self.route("POST")

    def do_PUT(self):
        self.route("PUT")

    def do_DELETE(self):
        self.route("DELETE")

    def route(self, method):
        global STATE
        url = urlparse(self.path)
        path, q = url.path, {k: v[-1] for k, v in parse_qs(url.query).items()}
        if path == "/_mock/state":
            return self.send(200, {k: v for k, v in STATE.items()})
        if path == "/_mock/reset":
            STATE = fresh()
            return self.send(200, {"ok": True})
        if path == "/_mock/set":
            changes = self.body() or {}
            # "book_hashes": {"101": "<32 hex>"}: a book's file is the one with that fingerprint
            # (for a test that puts a real book on the device)
            for bid, h in (changes.pop("book_hashes", None) or {}).items():
                for b in BOOKS:
                    if str(b["id"]) == str(bid):
                        b["hash"] = h
            STATE.update(changes)
            return self.send(200, {"ok": True})
        if STATE["offline"]:
            return self.error(503, "Service Unavailable")
        if not path.startswith("/api/v1/"):
            return self.error(404, "Not Found")
        p = path[len("/api/v1/"):]
        if p.startswith("koreader/"):
            if not self.ko_user():
                return
            STATE["seen"].append([method, p])
            return self.koreader(method, p[len("koreader/"):], q)
        if p == "auth/me" and method == "GET":
            if not self.api_key():
                return
            return self.send(200, {"id": 1, "username": "will", "name": "Will", "email": "will@example.com", "active": True,
                                   "isSuperuser": False, "isDefaultPassword": False, "settings": {}, "avatarUrl": None,
                                   "provisioningMethod": "local", "authenticationMethod": "api_key",
                                   "permissions": ["koreader_sync", "book_download"]})
        if p == "books/query" and method == "POST":
            # Marked safe for read-only keys in the real server. Only the part GZreader uses: the
            # audiobooks, found by a format rule. (The real card has many more fields.)
            if not self.api_key():
                return
            d = self.body()
            pg = isinstance(d, dict) and d.get("pagination")
            if not isinstance(pg, dict) or not isinstance(pg.get("page"), int) or not isinstance(pg.get("size"), int) \
                    or not isinstance(d.get("sort"), list):
                return self.error(400, "sort and pagination are required")
            rules = (d.get("filter") or {}).get("rules") or []
            fmts = {str(v).lower() for r in rules if r.get("field") == "format" and r.get("operator") == "includesAny"
                    for v in r.get("value") or []}
            items = [{"id": AUDIOBOOK["id"], "title": AUDIOBOOK["title"], "authors": AUDIOBOOK["authors"]}] \
                if not rules or fmts & {a["format"] for a in AUDIOBOOK["assets"]} else []
            items = items[(pg["page"] - 1) * pg["size"]:pg["page"] * pg["size"]]
            return self.send(201, {"items": items, "total": len(items), "page": pg["page"], "size": pg["size"]})
        if p.startswith("audiobooks/"):
            if not self.api_key(write=method != "GET"):
                return
            STATE["seen"].append([method, p])
            return self.audiobooks(method, p[len("audiobooks/"):])
        return self.error(404, "Not Found")

    # KOReader API ------------------------------------------------------------
    def koreader(self, method, p, q):
        if p == "users/auth" and method == "GET":
            return self.send(200, {"authorized": "OK", "username": KO_USER})
        if p == "plugin/version" and method == "GET":
            return self.send(200, {"pluginVersion": "0.9.0", "serverVersion": "0.9.0", "capabilities": STATE["capabilities"]})
        m = re.match(r"^syncs/progress/([^/]+)$", p)
        if m and method == "GET":
            p = STATE["progress"].get(m.group(1))
            return self.send(200, p and {"document": m.group(1), "percentage": p["percentage"], "progress": p.get("progress") or "",
                                         "device": p["device"], "device_id": p["device_id"], "timestamp": p["timestamp"]} or {})
        if p == "syncs/progress" and method == "PUT":
            d = self.body()
            if not isinstance(d, dict) or not isinstance(d.get("document"), str):
                return self.error(400, "document must be a string")
            if not isinstance(d.get("percentage"), (int, float)) or not 0 <= d["percentage"] <= 1:
                return self.error(400, "percentage must be a number from 0 to 1")
            if not any(b["hash"] == d["document"] for b in BOOKS):
                return self.error(404, "Book not found for the given document hash")
            self.keep_progress(d["document"], d, d.get("device"), d.get("device_id"))
            return self.send(200, {"document": d["document"], "timestamp": STATE["progress"][d["document"]]["timestamp"]})
        if p == "plugin/match-check" and method == "POST":
            d = self.body()
            if not self.device(d):
                return
            hashes = d.get("hashes")
            if not isinstance(hashes, list) or not 1 <= len(hashes) <= 500 or not all(isinstance(h, str) and MD5.match(h) for h in hashes):
                return self.error(400, "hashes must be 1 to 500 MD5 hex strings")
            by = {b["hash"]: b for b in BOOKS}
            return self.send(201, {"matches": [{"hash": h, "bookId": by[h]["id"], "bookFileId": by[h]["fileId"]} for h in hashes if h in by],
                                   "libraryVersion": "lib-%d" % len(BOOKS)})
        if p == "plugin/progress" and method == "POST":
            d = self.body()
            if not self.device(d):
                return
            items = d.get("items")
            if not isinstance(items, list) or not items:
                return self.error(400, "items must be a non-empty array")
            by = {b["hash"] for b in BOOKS}
            results, unmatched = [], []
            for it in items:
                if not isinstance(it, dict) or not isinstance(it.get("hash"), str) or not MD5.match(it["hash"]):
                    return self.error(400, "hash must be an MD5 hex string")
                if not isinstance(it.get("percentage"), (int, float)) or not 0 <= it["percentage"] <= 1:
                    return self.error(400, "percentage must be a number from 0 to 1")
                if "progress" in it and not isinstance(it["progress"], str):
                    return self.error(400, "progress must be a string")
                if it["hash"] in by:
                    self.keep_progress(it["hash"], it, d["deviceModel"], d["deviceId"])
                    results.append({"hash": it["hash"], "accepted": True})
                else:
                    unmatched.append(it["hash"])
            return self.send(201, {"results": results, "unmatched": unmatched})
        if p.startswith("plugin/catalog/") and method == "GET":
            return self.catalog(p[len("plugin/catalog/"):], q)
        return self.error(404, "Not Found")

    def keep_progress(self, h, src, device, device_id):
        STATE["progress"][h] = {"percentage": src["percentage"], "progress": src.get("progress"), "device": device or "KOReader",
                                "device_id": device_id or "mock", "timestamp": int(src.get("timestamp") or time.time()),
                                "updatedAt": time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime())}

    def page(self, items, q, base):
        try:
            size = int(q.get("size", 20))
            page = int(q.get("page", 1))
        except ValueError:
            return self.error(400, "page and size must be integers")
        if not 1 <= size <= 100 or page < 1:
            return self.error(400, "size must be from 1 to 100 and page at least 1")
        start = (page - 1) * size
        part = items[start:start + size]
        more = start + size < len(items)
        return self.send(200, {"items": part, "total": len(items), "page": page, "size": size, "hasNext": more,
                               "hasPrevious": page > 1,
                               "nextUrl": more and "%s&page=%d" % (base, page + 1) or None,
                               "previousUrl": page > 1 and "%s&page=%d" % (base, page - 1) or None,
                               "seriesSummary": None})

    def catalog(self, p, q):
        C = "/api/v1/koreader/plugin/catalog"
        if p == "root":
            return self.send(200, {"sections": [
                {"id": "continue-reading", "title": "Continue reading", "section": "continue-reading",
                 "booksHref": C + "/books?sort=recently_read&readStatus=reading"},
                {"id": "recent", "title": "Recently added", "section": "recent", "booksHref": C + "/books?sort=recently_added"},
                {"id": "libraries", "title": "Libraries", "section": "libraries", "href": C + "/sections/libraries"},
                {"id": "collections", "title": "Collections", "section": "collections", "href": C + "/sections/collections"},
                {"id": "smart-scopes", "title": "SmartScopes", "section": "smart-scopes", "href": C + "/sections/smart-scopes"},
                {"id": "authors", "title": "Authors", "section": "authors", "href": C + "/sections/authors"},
                {"id": "series", "title": "Series", "section": "series", "href": C + "/sections/series"},
                {"id": "all-books", "title": "All Books", "section": "all-books", "booksHref": C + "/books?sort=title"}]})
        m = re.match(r"^sections/([^/]+)$", p)
        if m:
            s = m.group(1)
            if s == "libraries":
                return self.send(200, {"section": s, "items": [
                    {"id": str(i), "title": n, "section": s, "count": sum(b["libraryId"] == i for b in BOOKS),
                     "booksHref": C + "/books?sort=title&libraryId=%d" % i} for i, n in LIBRARIES.items()]})
            if s == "collections":
                return self.send(200, {"section": s, "items": [
                    {"id": str(i), "title": n, "section": s, "count": sum(i in b["collections"] for b in BOOKS),
                     "booksHref": C + "/books?sort=title&collectionId=%d" % i} for i, n in COLLECTIONS.items()]})
            if s == "smart-scopes":
                return self.send(200, {"section": s, "items": []})
            if s == "authors":
                names = sorted({a for b in BOOKS for a in b["authors"]})
                items = [{"id": n, "title": n, "section": s, "count": sum(n in b["authors"] for b in BOOKS),
                          "booksHref": C + "/books?sort=title&author=" + quote(n), "authorId": i + 1, "hasPhoto": False,
                          "photoUrl": None} for i, n in enumerate(names)]
            elif s == "series":
                names = sorted({b["seriesName"] for b in BOOKS if b["seriesName"]})
                items = []
                for n in names:
                    sid = next(b["seriesId"] for b in BOOKS if b["seriesName"] == n)
                    items.append({"id": "series-%d" % sid, "title": n, "section": s, "count": sum(b["seriesName"] == n for b in BOOKS),
                                  "seriesId": sid, "booksHref": C + "/books?sort=series&seriesId=%d" % sid,
                                  "authorNames": sorted({a for b in BOOKS if b["seriesName"] == n for a in b["authors"]})})
            else:
                return self.error(400, "Unknown catalog section")
            # (authors and series are the two sections the real server pages)
            return self.send(200, {"section": s, "items": items, "page": 1, "hasNext": False, "hasPrevious": False,
                                   "nextUrl": None, "previousUrl": None, "query": None, "total": len(items)})
        if p == "books":
            if q.get("sort", "recently_added") not in SORTS:
                return self.error(400, "sort must be one of " + ", ".join(sorted(SORTS)))
            books = list(BOOKS)
            if "readStatus" in q:
                if q["readStatus"] not in ("unread", "reading", "finished"):
                    return self.error(400, "readStatus must be one of unread, reading, finished")
                reading = lambda b: b["hash"] in STATE["progress"]
                books = [b for b in books if {"reading": reading(b), "unread": not reading(b), "finished": False}[q["readStatus"]]]
            for key, test in (("libraryId", lambda b, v: b["libraryId"] == int(v)),
                              ("collectionId", lambda b, v: int(v) in b["collections"]),
                              ("seriesId", lambda b, v: b["seriesId"] == int(v)),
                              ("author", lambda b, v: v in b["authors"]),
                              ("series", lambda b, v: b["seriesName"] == v),
                              ("format", lambda b, v: b["format"] == v.lower()),
                              ("q", lambda b, v: v.lower() in (b["title"] + " " + " ".join(b["authors"])).lower())):
                if key in q:
                    try:
                        books = [b for b in books if test(b, q[key])]
                    except ValueError:
                        return self.error(400, "%s must be a number" % key)
            sort = q.get("sort", "recently_added")
            keyf = {"title": lambda b: b["title"].lower(), "author": lambda b: b["authors"][0].lower(),
                    "series": lambda b: ((b["seriesName"] or "~"), b["seriesIndex"] or 0)}.get(sort, lambda b: b["addedAt"])
            desc = q.get("order", "desc" if sort.startswith("recently") else "asc") == "desc"
            books.sort(key=keyf, reverse=desc)
            base = "/api/v1/koreader/plugin/catalog/books?" + "&".join("%s=%s" % (k, v) for k, v in sorted(q.items()) if k != "page")
            return self.page([list_item(b) for b in books], q, base)
        m = re.match(r"^books/(\d+)$", p)
        if m:
            b = next((b for b in BOOKS if b["id"] == int(m.group(1))), None)
            return self.send(200, detail(b)) if b else self.error(404, "Book not found")
        m = re.match(r"^books/(\d+)/thumbnail$", p)
        if m:
            if not any(b["id"] == int(m.group(1)) for b in BOOKS):
                return self.error(404, "No thumbnail")
            if self.headers.get("If-None-Match") == '"1790000000000"':
                return self.send(304, b"", "image/png")
            return self.send(200, PNG, "image/png", {"ETag": '"1790000000000"', "Cache-Control": "no-cache"})
        m = re.match(r"^files/(\d+)/download$", p)
        if m:
            b = next((b for b in BOOKS if b["fileId"] == int(m.group(1))), None)
            if not b:
                return self.error(404, "File not found")
            return self.send(200, b["data"], "application/epub+zip" if b["format"] == "epub" else "application/pdf",
                             {"Content-Disposition": 'attachment; filename="%s.%s"' % (b["title"], b["format"])})
        return self.error(404, "Not Found")

    # Main API: audiobooks ------------------------------------------------------
    def audiobooks(self, method, p):
        m = re.match(r"^(\d+)/(.+)$", p)
        if not m or int(m.group(1)) != AUDIOBOOK["id"]:
            return self.error(404, "Book has no audiobook assets")
        rest, bid = m.group(2), AUDIOBOOK["id"]
        if rest == "manifest" and method == "GET":
            assets = [{"assetId": a["assetId"], "fileId": a["fileId"], "sequence": a["sequence"], "format": a["format"],
                       "durationMs": a["durationMs"], "sizeBytes": len(a["data"]),
                       "etag": hashlib.md5(a["data"]).hexdigest()} for a in AUDIOBOOK["assets"]]
            chapters, at = [], 0
            for a in AUDIOBOOK["assets"]:
                chapters.append({"id": "ch-%d" % a["sequence"], "title": "Part %d" % (a["sequence"] + 1), "assetId": a["assetId"],
                                 "sequence": a["sequence"], "startMs": at, "endMs": at + a["durationMs"], "assetOffsetMs": 0})
                at += a["durationMs"]
            return self.send(200, {"schema": "bookorbit.audiobook-manifest", "schemaVersion": 2, "revision": manifest_revision(),
                                   "book": {"id": bid, "title": AUDIOBOOK["title"], "authors": AUDIOBOOK["authors"],
                                            "narrators": AUDIOBOOK["narrators"], "hasCover": True},
                                   "assets": assets, "chapters": chapters, "totalDurationMs": at})
        m = re.match(r"^assets/([^/]+)/content$", rest)
        if m and method == "GET":
            a = next((a for a in AUDIOBOOK["assets"] if a["assetId"] == m.group(1)), None)
            if not a:
                return self.error(404, "Audiobook asset not found")
            data, size = a["data"], len(a["data"])
            rng = re.match(r"bytes=(\d+)-(\d*)", self.headers.get("Range") or "")
            if rng:
                start = int(rng.group(1))
                end = int(rng.group(2)) if rng.group(2) else size - 1
                if start >= size or end < start or end >= size:
                    return self.send(416, b"", "audio/mpeg", {"Content-Range": "bytes */%d" % size})
                return self.send(206, data[start:end + 1], "audio/mpeg",
                                 {"Accept-Ranges": "bytes", "Content-Range": "bytes %d-%d/%d" % (start, end, size)})
            return self.send(200, data, "audio/mpeg", {"Accept-Ranges": "bytes"})
        if rest == "playback-state":
            cur = STATE["playback"].get(bid)
            if method == "GET":
                if not cur:
                    return self.send(200, b"")  # null: the real server sends 200 with no body
                return self.send(200, {k: v for k, v in cur.items() if k != "operationId"})
            if method == "DELETE":
                STATE["playback"].pop(bid, None)
                return self.send(204, b"")
            if method == "PUT":
                d = self.body()
                if not isinstance(d, dict):
                    return self.error(400, "Bad JSON")
                checks = (("assetId", lambda v: isinstance(v, str) and ASSET_ID.match(v)),
                          ("positionMs", lambda v: isinstance(v, int) and not isinstance(v, bool) and v >= 0),
                          ("capturedAt", lambda v: isinstance(v, str) and ISO.match(v)),
                          ("operationId", lambda v: isinstance(v, str) and UUID.match(v)),
                          ("baseRevision", lambda v: isinstance(v, int) and not isinstance(v, bool) and v >= 0),
                          ("manifestRevision", lambda v: isinstance(v, str) and re.match(r"^[0-9a-f]{64}$", v)))
                for name, ok in checks:
                    if not ok(d.get(name)):
                        return self.error(400, "%s is not valid" % name)
                extra = set(d) - {n for n, _ in checks}
                if extra:
                    return self.error(400, "property %s should not exist" % sorted(extra)[0])
                if d["manifestRevision"] != manifest_revision():
                    return self.error(412, "Audiobook manifest has changed")
                a = next((a for a in AUDIOBOOK["assets"] if a["assetId"] == d["assetId"]), None)
                if not a:
                    return self.error(400, "assetId does not belong to this audiobook")
                if cur and cur.get("operationId") == d["operationId"]:
                    return self.send(200, {k: v for k, v in cur.items() if k != "operationId"})  # a resend: no change
                if d["positionMs"] > a["durationMs"] + 1000:
                    return self.error(400, "positionMs exceeds the asset duration")
                if d["baseRevision"] != (cur["revision"] if cur else 0):
                    return self.error(409, "Playback state revision conflict")
                pos = min(d["positionMs"], a["durationMs"])
                total = sum(x["durationMs"] for x in AUDIOBOOK["assets"])
                before = sum(x["durationMs"] for x in AUDIOBOOK["assets"] if x["sequence"] < a["sequence"])
                pct = max(0.0, min(100.0, (before + pos) * 100.0 / total))
                STATE["playback"][bid] = {"assetId": d["assetId"], "positionMs": pos, "percentage": pct,
                                          "completed": pct >= 100, "capturedAt": d["capturedAt"],
                                          "revision": (cur["revision"] if cur else 0) + 1,
                                          "manifestRevision": d["manifestRevision"], "operationId": d["operationId"]}
                return self.send(200, {k: v for k, v in STATE["playback"][bid].items() if k != "operationId"})
        return self.error(404, "Not Found")


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 18096
    print("mock BookOrbit on 127.0.0.1:%d (KOReader user %s, API key %s...)" % (port, KO_USER, API_KEY[:8]), flush=True)
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
