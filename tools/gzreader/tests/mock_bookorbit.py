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
import hashlib, io, json, re, sys, time, zipfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs, quote

KO_USER, KO_PASSWORD = "will-kindle", "hunter22"
KO_KEY = hashlib.md5(KO_PASSWORD.encode()).hexdigest()
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


def book(i, title, authors, library, series=None, idx=None, fmt="epub", collections=(), genres=()):
    data = ("%s by %s\n" % (title, ", ".join(authors))).encode() * 40
    return {"id": i, "title": title, "authors": authors, "libraryId": library, "seriesName": series,
            "seriesId": (900 + sum(map(ord, series)) % 90) if series else None, "seriesIndex": idx,
            "format": fmt, "fileId": 5000 + i, "data": data, "hash": hashlib.md5(data).hexdigest(),
            "collections": list(collections), "genres": list(genres), "addedAt": "2026-10-%02dT08:00:00.000Z" % (i % 27 + 1),
            "updatedAt": "2026-11-%02dT09:30:00.000Z" % (i % 20 + 1)}


LIBRARIES = {1: "Fiction", 2: "Non-fiction"}
COLLECTIONS = {11: "Beach reads", 12: "Book club"}
COLLECTION_OWNERS = {}  # collection id -> user id, for the ones that aren't the signed-in user's (id 1)
BOOKS = [
    book(101, "The Long Way Round", ["Ada Marsh"], 1, "Waymarks", 1, collections=[11], genres=["Travel"]),
    book(102, "The Short Way Back", ["Ada Marsh"], 1, "Waymarks", 2, genres=["Travel", "Memoir"]),
    book(103, "A Field Guide to Fog", ["Ben Okafor"], 2, collections=[12], genres=["Nature"]),
    book(104, "Night Trains", ["Clara Voss", "Ben Okafor"], 1, collections=[11, 12]),
    book(105, "Tide Tables", ["Dmitri Hale"], 2, fmt="pdf"),
]
AUDIOBOOK = {
    "id": 201, "title": "The Long Way Round", "authors": ["Ada Marsh"], "narrators": ["June Park"], "genres": ["Travel"],
    "assets": [
        {"assetId": "aud_11111111-1111-4111-8111-111111111111", "fileId": 6201, "sequence": 0, "format": "mp3",
         "durationMs": 60000, "data": b"ID3" + b"\0" * 4000},
        {"assetId": "aud_22222222-2222-4222-8222-222222222222", "fileId": 6202, "sequence": 1, "format": "mp3",
         "durationMs": 45000, "data": b"ID3" + b"\1" * 3000},
    ],
}
# A second audiobook: one M4B file with chapters inside it (and a book that is also ebook 102).
AUDIOBOOK_2 = {
    "id": 102, "title": "The Short Way Back", "authors": ["Ada Marsh"], "narrators": ["June Park", "Sam Lee"],
    "assets": [{"assetId": "aud_33333333-3333-4333-8333-333333333333", "fileId": 6301, "sequence": 0, "format": "m4b",
                "durationMs": 600000, "data": b"\0\0\0\x20ftypM4B " + b"\2" * 5000}],
    "chapters": [("Opening", 0, 200000), ("Middle", 200000, 400000), ("End", 400000, 600000)],
}
AUDIOBOOKS = {201: AUDIOBOOK, 102: AUDIOBOOK_2}


def fresh():
    return {
        "capabilities": list(CAPABILITIES),
        "sync_enabled": True,     # the KOReader credentials' "sync enabled" switch
        "waf_block": False,       # True: a firewall in front refuses the KOReader plugin's POSTs (403, an HTML page)
        "ko_permission": True,    # the account's KOReader sync permission
        "api_keys_enabled": True,
        "api_key_write": True,    # False: a read key (PUT answers 403 API_KEY_READ_ONLY)
        "offline": False,         # every route answers 503
        "ko_credentials": True,   # the account has a KOReader sync sign-in (False: none yet; the API key can make one)
        "ko_made": None,          # {username, md5}: the sign-in made through POST koreader/credentials
        "ko_md5_known": True,     # False: an old sign-in whose key the server can't hand over (plugin-package answers 400)
        "key_ko_permission": True,  # the API key's "KOReader sync" permission
        "ko_delivery": None,      # the sync sign-in's read-aloud EPUB delivery: None (Automatic), "audioless_epub", "original"
        "ko_names_taken": [],     # sync user names other accounts have
        "goal_books": 30,         # the year's reading goal (None: no goal set)
        "achievements": True,     # False: the reader switched badges off (the dashboard sends null)
        "reading_year": True,     # False: a server from before the dashboard sent minutes per day
        "cors_origin": None,      # a site a reverse proxy in front lets in (BookOrbit itself sends no CORS headers)
        "requests": [],           # book requests: {id, userId, title, authors, mediaKind, status, ...}
        "request_permission": True,  # the "Request books" permission (False: 403)
        "request_status": "pending",  # what a new request starts as ("approved" with auto-approve)
        "progress": {},           # hash -> {percentage, progress, device, device_id, timestamp}
        "playback": {},           # book id -> state
        "seen": [],               # (method, path) of signed-in requests, newest last
        "devices": {},            # deviceId -> deviceModel
        "annotations": {},        # book id -> [server highlights: serverId, version, key, datetime, ..., deleted]
        "anno_devices": {},       # "<deviceId>:<bookId>" -> {serverId (as text): the version that device has}
        "bookmarks": {},          # book id -> [server bookmarks: serverId, pos, pageno, title, deleted]
        "mark_devices": {},       # "<deviceId>:<bookId>" -> {serverId (as text): that device's key for it}
        "page_stats": {},         # hash -> [[page, startTime, durationSeconds, totalPages]] (one per page and start)
        "ratings": {},            # book id -> stars (0-5)
        "next_id": 1,
    }


STATE = fresh()


def manifest_revision(ab=None):
    h = hashlib.sha256()
    for a in (ab or AUDIOBOOK)["assets"]:
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


# (a read-along book: its EPUB has narration. Asked for with ?variant=original it comes
# with it (bigger); otherwise without, and the size of that copy is only known once
# BookOrbit has made it: STATE["audioless_made"])
NARRATED = {104}


def narrated_data(b):
    return b["data"] + b"narration " * 2000


def detail(b, variant=None):
    d = list_item(b)
    p = STATE["progress"].get(b["hash"])
    d.update({"subtitle": None, "description": "About %s." % b["title"], "publisher": "Example House",
              "publishedDate": "2020-05-01", "publishedYear": 2020, "language": "en", "isbn10": None, "isbn13": None,
              "libraryId": b["libraryId"], "libraryName": LIBRARIES[b["libraryId"]], "rating": STATE["ratings"].get(str(b["id"])), "pageCount": 240,
              "collections": [{"id": c, "name": COLLECTIONS[c]} for c in b["collections"]], "genres": list(b.get("genres") or []), "tags": [],
              "progress": p and {"fileId": b["fileId"], "percentage": pct100(p["percentage"]),
                                 "koreaderProgress": p.get("progress"), "updatedAt": p["updatedAt"]} or None,
              "files": [{"id": b["fileId"], "format": b["format"], "role": "primary", "downloadVariant": "original",
                         "sizeBytes": len(b["data"]), "sourceSizeBytes": len(b["data"]), "durationSeconds": None, "fileHash": b["hash"],
                         "downloadUrl": "/api/v1/koreader/plugin/catalog/files/%d/download" % b["fileId"],
                         "devicePath": "%s/%s.%s" % (b["authors"][0], b["title"], b["format"])}],
              "relatedSections": []})
    if b["id"] in NARRATED:
        f = d["files"][0]
        f["sourceMediaOverlayAvailable"] = True
        f["sourceSizeBytes"] = len(narrated_data(b))
        if variant == "original":
            f.update({"sizeBytes": len(narrated_data(b)), "narrationPlaybackAvailable": True,
                      "downloadUrl": f["downloadUrl"] + "?variant=original&selection=sel-original"})
        elif variant == "audioless_epub":
            f.update({"downloadVariant": "audioless_epub",
                      "sizeBytes": len(b["data"]) if STATE.get("audioless_made") else None,
                      "downloadUrl": f["downloadUrl"] + "?variant=audioless_epub&selection=sel-audioless"})
    return d


# ---------------------------------------------------------------- highlights (the exchange)
DRAWERS = {"lighten", "underscore", "strikeout", "invert"}
CONTENT = ("drawer", "color", "text", "note", "chapter")


def anno_key(datetime, pos0):
    """A highlight's identity on the device: md5 of "<datetime>|<pos0>", as the plugin and server make it."""
    return hashlib.md5(("%s|%s" % (datetime, pos0)).encode()).hexdigest()


def check_exchange_book(book):
    if not isinstance(book, dict) or not isinstance(book.get("hash"), str) or not MD5.match(book["hash"]):
        return "hash must be an MD5 hex string"
    keys = book.get("keys")
    if not isinstance(keys, list) or len(keys) > 5000:
        return "keys must be an array of at most 5000"
    for k in keys:
        if not isinstance(k, dict) or not isinstance(k.get("k"), str) or not MD5.match(k["k"]) \
                or not isinstance(k.get("dt"), str) or not DEVICE_TIME.match(k["dt"]):
            return "each key needs k (MD5 hex) and dt (YYYY-MM-DD HH:MM:SS)"
    if not isinstance(book.get("keysComplete"), bool):
        return "keysComplete must be a boolean"
    if "sidecarState" in book and book["sidecarState"] not in ("known", "new"):
        return "sidecarState must be known or new"
    changes = book.get("changes")
    if not isinstance(changes, list) or len(changes) > 50:
        return "changes must be an array of at most 50"
    for c in changes:
        if not isinstance(c, dict) or not isinstance(c.get("datetime"), str) or not DEVICE_TIME.match(c["datetime"]):
            return "datetime must be YYYY-MM-DD HH:MM:SS"
        if "datetimeUpdated" in c and not (isinstance(c["datetimeUpdated"], str) and DEVICE_TIME.match(c["datetimeUpdated"])):
            return "datetimeUpdated must be YYYY-MM-DD HH:MM:SS"
        if c.get("drawer") not in DRAWERS:
            return "drawer must be one of lighten, underscore, strikeout, invert"
        if c.get("posFormat") not in ("xpointer", "pdf"):
            return "posFormat must be xpointer or pdf"
        if not isinstance(c.get("pos0"), str) or not c["pos0"] or len(c["pos0"]) > 4000:
            return "pos0 must be a string"
        for name, limit in (("color", 30), ("text", 10000), ("note", 5000), ("chapter", 500), ("pos1", 4000)):
            if name in c and not (isinstance(c[name], str) and len(c[name]) <= limit):
                return "%s must be a string of at most %d characters" % (name, limit)
        if "pageno" in c and not (isinstance(c["pageno"], int) and not isinstance(c["pageno"], bool) and c["pageno"] >= 0):
            return "pageno must be a whole number"
        extra = set(c) - {"datetime", "datetimeUpdated", "drawer", "color", "text", "note", "chapter", "pageno", "posFormat", "pos0", "pos1"}
        if extra:
            return "property %s should not exist" % sorted(extra)[0]
    return None


def check_ack_book(book):
    if not isinstance(book, dict) or not isinstance(book.get("hash"), str) or not MD5.match(book["hash"]):
        return "hash must be an MD5 hex string"
    for name in ("applied", "deleted"):
        rows = book.get(name)
        if not isinstance(rows, list) or len(rows) > 200:
            return "%s must be an array of at most 200" % name
        for r in rows:
            if not isinstance(r, dict) or not isinstance(r.get("serverId"), int) or r["serverId"] < 1 or r.get("status") not in ("applied", "failed"):
                return "%s entries need serverId and status (applied or failed)" % name
            if name == "applied" and not (isinstance(r.get("version"), int) and r["version"] >= 1):
                return "applied entries need version"
    return None


def exchange_book(device_id, b, book):
    """One book's exchange: take the device's changes and deletions, answer with what it lacks."""
    anns = STATE["annotations"].setdefault(str(b["id"]), [])
    dev_key = "%s:%d" % (device_id, b["id"])
    if book.get("sidecarState") == "new":
        STATE["anno_devices"][dev_key] = {}   # a fresh copy: nothing deleted, everything offered again
    has = STATE["anno_devices"].setdefault(dev_key, {})
    created = updated = unchanged = device_deleted = 0
    for c in book["changes"]:
        key = anno_key(c["datetime"], c["pos0"])
        a = next((a for a in anns if a["key"] == key and not a["deleted"]), None)
        fields = {f: c.get(f) for f in CONTENT}
        fields["color"] = fields["color"] or "yellow"
        fields["text"] = fields["text"] or ""
        if a is None:
            a = dict(fields, serverId=STATE["next_id"], version=1, key=key, datetime=c["datetime"],
                     datetimeUpdated=c.get("datetimeUpdated"), pos0=c["pos0"], pos1=c.get("pos1"), pageno=c.get("pageno"),
                     posFormat=c["posFormat"], deleted=False)
            STATE["next_id"] += 1
            anns.append(a)
            created += 1
        elif any(a[f] != fields[f] for f in CONTENT):
            a.update(fields)
            a["version"] += 1
            a["datetimeUpdated"] = c.get("datetimeUpdated") or a["datetimeUpdated"]
            updated += 1
        else:
            unchanged += 1
        has[str(a["serverId"])] = a["version"]
    if book["keysComplete"] and book.get("sidecarState") != "new":
        present = {k["k"] for k in book["keys"]}
        for a in anns:
            if not a["deleted"] and str(a["serverId"]) in has and a["key"] not in present:
                a["deleted"] = True      # removed on the device
                has.pop(str(a["serverId"]), None)
                device_deleted += 1
    add, edit, delete = [], [], []
    for a in anns:
        sid = str(a["serverId"])
        if a["deleted"]:
            if sid in has:
                delete.append({"serverId": a["serverId"], "key": a["key"], "datetime": a["datetime"]})
        elif sid not in has:
            add.append({k: a[k] for k in ("serverId", "version", "datetime", "datetimeUpdated", "drawer", "color", "text", "note",
                                           "chapter", "posFormat", "pos0", "pos1", "pageno")})
        elif has[sid] < a["version"]:
            edit.append({"serverId": a["serverId"], "version": a["version"], "key": a["key"], "datetime": a["datetime"],
                         "datetimeUpdated": a["datetimeUpdated"] or a["datetime"], "drawer": a["drawer"], "color": a["color"],
                         "text": a["text"], "note": a["note"], "chapter": a["chapter"]})
    return {"hash": b["hash"], "bookId": b["id"],
            "applied": {"created": created, "updated": updated, "unchanged": unchanged, "deviceDeleted": device_deleted},
            "toApply": {"add": add[:50], "edit": edit, "delete": delete}, "more": len(add) > 50, "skippedNoPosition": 0}


def ack_book(device_id, b, book):
    has = STATE["anno_devices"].setdefault("%s:%d" % (device_id, b["id"]), {})
    acked = 0
    for r in book["applied"]:
        if r["status"] == "applied":
            has[str(r["serverId"])] = r["version"]
            acked += 1
    for r in book["deleted"]:
        if r["status"] == "applied":
            has.pop(str(r["serverId"]), None)
            acked += 1
    return {"hash": b["hash"], "acked": acked}


def web_highlight(w):
    """What the web reader would do: {"book": id, "op": "add"|"edit"|"delete", ...}. Returns the highlight."""
    anns = STATE["annotations"].setdefault(str(w["book"]), [])
    if w["op"] == "add":
        a = {"serverId": STATE["next_id"], "version": 1, "datetime": w.get("datetime", "2026-11-22 10:00:00"), "datetimeUpdated": None,
             "drawer": w.get("drawer", "lighten"), "color": w.get("color", "yellow"), "text": w.get("text", ""), "note": w.get("note"),
             "chapter": w.get("chapter"), "posFormat": "xpointer", "pos0": w["pos0"], "pos1": w.get("pos1"), "pageno": w.get("pageno"),
             "deleted": False}
        a["key"] = anno_key(a["datetime"], a["pos0"])
        STATE["next_id"] += 1
        anns.append(a)
        return a
    a = next(a for a in anns if a["serverId"] == w["serverId"])
    if w["op"] == "delete":
        a["deleted"] = True
    else:
        for f in CONTENT:
            if f in w:
                a[f] = w[f]
        a["version"] += 1
        a["datetimeUpdated"] = w.get("datetimeUpdated", "2026-11-22 12:00:00")
    return a


# ---------------------------------------------------------------- bookmarks (the exchange)
def check_mark_book(book):
    if not isinstance(book, dict) or not isinstance(book.get("hash"), str) or not MD5.match(book["hash"]):
        return "hash must be an MD5 hex string"
    keys = book.get("keys")
    if not isinstance(keys, list) or len(keys) > 2000:
        return "keys must be an array of at most 2000"
    for k in keys:
        if not isinstance(k, dict) or not isinstance(k.get("k"), str) or not MD5.match(k["k"]) \
                or not isinstance(k.get("dt"), str) or not DEVICE_TIME.match(k["dt"]):
            return "each key needs k (MD5 hex) and dt (YYYY-MM-DD HH:MM:SS)"
    if not isinstance(book.get("keysComplete"), bool):
        return "keysComplete must be a boolean"
    if "sidecarState" in book and book["sidecarState"] not in ("known", "new"):
        return "sidecarState must be known or new"
    changes = book.get("changes")
    if not isinstance(changes, list) or len(changes) > 50:
        return "changes must be an array of at most 50"
    for c in changes:
        if not isinstance(c, dict) or not isinstance(c.get("datetime"), str) or not DEVICE_TIME.match(c["datetime"]):
            return "datetime must be YYYY-MM-DD HH:MM:SS"
        if not isinstance(c.get("pos"), str) or not c["pos"] or len(c["pos"]) > 4000:
            return "pos must be a string"
        for name in ("chapter", "note"):
            if name in c and not (isinstance(c[name], str) and len(c[name]) <= 500):
                return "%s must be a string of at most 500 characters" % name
        if "pageno" in c and not (isinstance(c["pageno"], int) and not isinstance(c["pageno"], bool) and c["pageno"] >= 0):
            return "pageno must be a whole number"
        extra = set(c) - {"datetime", "datetimeUpdated", "pos", "pageno", "chapter", "note"}
        if extra:
            return "property %s should not exist" % sorted(extra)[0]
    return None


def check_mark_ack(book):
    if not isinstance(book, dict) or not isinstance(book.get("hash"), str) or not MD5.match(book["hash"]):
        return "hash must be an MD5 hex string"
    for name in ("applied", "deleted"):
        rows = book.get(name)
        if not isinstance(rows, list) or len(rows) > 200:
            return "%s must be an array of at most 200" % name
        for r in rows:
            if not isinstance(r, dict) or not isinstance(r.get("serverId"), int) or r["serverId"] < 1 or r.get("status") not in ("applied", "failed"):
                return "%s entries need serverId and status (applied or failed)" % name
            if "key" in r and not (isinstance(r["key"], str) and MD5.match(r["key"])):
                return "key must be an MD5 hex string"
    return None


def mark_exchange(device_id, b, book):
    marks = STATE["bookmarks"].setdefault(str(b["id"]), [])
    dev_key = "%s:%d" % (device_id, b["id"])
    if book.get("sidecarState") == "new":
        STATE["mark_devices"][dev_key] = {}
    links = STATE["mark_devices"].setdefault(dev_key, {})
    accepted = duplicates = device_deleted = 0
    for c in book["changes"]:
        key = anno_key(c["datetime"], c["pos"])
        m = next((m for m in marks if m["pos"] == c["pos"] and not m["deleted"]), None)
        if m is None:
            m = {"serverId": STATE["next_id"], "pos": c["pos"], "pageno": c.get("pageno"), "title": c.get("note") or c.get("chapter") or "",
                 "datetime": c["datetime"], "deleted": False}
            STATE["next_id"] += 1
            marks.append(m)
            accepted += 1
        else:
            duplicates += 1
        links[str(m["serverId"])] = key
    if book["keysComplete"] and book.get("sidecarState") != "new":
        present = {k["k"] for k in book["keys"]}
        for m in marks:
            sid = str(m["serverId"])
            if not m["deleted"] and sid in links and links[sid] not in present:
                m["deleted"] = True
                links.pop(sid, None)
                device_deleted += 1
    add = [{"serverId": m["serverId"], "pos": m["pos"], "pageno": m["pageno"], "title": m["title"]}
           for m in marks if not m["deleted"] and str(m["serverId"]) not in links]
    delete = [{"serverId": m["serverId"], "key": links[str(m["serverId"])], "datetime": m.get("datetime")}
              for m in marks if m["deleted"] and str(m["serverId"]) in links]
    return {"hash": b["hash"], "bookId": b["id"], "accepted": accepted, "duplicates": duplicates, "rejected": 0,
            "deviceDeleted": device_deleted, "toApply": {"add": add, "delete": delete}, "more": False, "skippedConversion": 0}


def mark_ack(device_id, b, book):
    links = STATE["mark_devices"].setdefault("%s:%d" % (device_id, b["id"]), {})
    acked = 0
    for r in book["applied"]:
        if r["status"] == "applied" and r.get("key"):
            links[str(r["serverId"])] = r["key"]
            acked += 1
    for r in book["deleted"]:
        if r["status"] == "applied":
            links.pop(str(r["serverId"]), None)
            acked += 1
    return {"hash": b["hash"], "acked": acked}


def web_bookmark(w):
    """What another device or the web would do: {"book": id, "op": "add"|"delete", ...}."""
    marks = STATE["bookmarks"].setdefault(str(w["book"]), [])
    if w["op"] == "add":
        m = {"serverId": STATE["next_id"], "pos": w["pos"], "pageno": w.get("pageno"), "title": w.get("title", ""), "datetime": None, "deleted": False}
        STATE["next_id"] += 1
        marks.append(m)
        return m
    m = next(m for m in marks if m["serverId"] == w["serverId"])
    m["deleted"] = True
    return m



def ebook_card(b):
    """A book as one of the main API's book cards (the fields GZreader reads)."""
    return {"id": b["id"], "title": b["title"], "authors": b["authors"], "seriesName": b["seriesName"],
            "seriesIndex": b["seriesIndex"], "hasCover": True, "genres": b.get("genres") or [],
            "readingProgress": None, "addedAt": b["addedAt"],
            "files": [{"id": b["fileId"], "format": b["format"], "role": "primary", "sizeBytes": len(b["data"])}]}


def audio_card(ab):
    """An audiobook as one of the main API's book cards (the real card has many more fields)."""
    state = STATE["playback"].get(ab["id"])
    return {"id": ab["id"], "title": ab["title"], "authors": ab["authors"], "narrators": ab["narrators"],
            "seriesName": None, "seriesIndex": None, "hasCover": True, "subtitle": None,
            "readingProgress": state and state["percentage"] or None, "genres": ab.get("genres") or [],
            "files": [{"id": a["fileId"], "format": a["format"]} for a in ab["assets"]]}


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
        if STATE.get("cors_origin") and self.headers.get("Origin") == STATE["cors_origin"]:
            self.send_header("Access-Control-Allow-Origin", STATE["cors_origin"])
            self.send_header("Access-Control-Expose-Headers", "content-length, content-range, content-disposition, etag")
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
        made = STATE["ko_made"]  # (a sign-in made with the API key stands in for the usual one)
        if not made and not STATE["ko_credentials"]:
            return self.error(401, "Invalid credentials")
        if user != (made["username"] if made else KO_USER):
            return self.error(401, "Invalid credentials")
        if not STATE["sync_enabled"]:
            return self.error(403, "Sync is disabled")
        want = made["md5"] if made else KO_KEY
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
    def do_OPTIONS(self):
        # (only a reverse proxy answers a browser's preflight: without one set up, as production BookOrbit, 404)
        allowed = STATE["cors_origin"]
        if not allowed or self.headers.get("Origin") != allowed:
            return self.error(404, "Cannot OPTIONS " + self.path.split("?")[0])
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", allowed)
        self.send_header("Access-Control-Allow-Headers", "x-auth-user, x-auth-key, authorization, content-type, range, if-none-match")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
        self.send_header("Content-Length", "0")
        self.end_headers()

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
        if STATE.get("waf_block") and method == "POST" and path.startswith("/api/v1/koreader/plugin/"):
            return self.send(403, b"<html><body><h1>403 Forbidden</h1>Request blocked.</body></html>", "text/html")
        if path == "/_mock/reset":
            STATE = fresh()
            return self.send(200, {"ok": True})
        if path == "/_mock/set":
            changes = self.body() or {}
            # "book_hashes": {"101": "<32 hex>"}: a book's file is the one with that fingerprint
            # (for a test that puts a real book on the device)
            mark = changes.pop("web_bookmark", None)
            if mark:
                return self.send(200, web_bookmark(mark))
            web = changes.pop("web_highlight", None)
            if web:
                return self.send(200, web_highlight(web))
            # "add_request": {"title", "mediaKind", "userId"?, "status"?, ...}: a request as the server has it
            add = changes.pop("add_request", None)
            if add:
                r = {"id": 500 + len(STATE["requests"]) + 1, "userId": 1, "authors": [], "mediaKind": "ebook", "status": "pending"}
                r.update(add)
                STATE["requests"].append(r)
                return self.send(200, {"id": r["id"]})
            # "request_update": {"id", ...}: what the server did with one (approved it, found it, ...)
            upd = changes.pop("request_update", None)
            if upd:
                for r in STATE["requests"]:
                    if r["id"] == upd.get("id"):
                        r.update(upd)
                return self.send(200, {"ok": True})
            for cid, owner in (changes.pop("collection_owners", None) or {}).items():
                COLLECTIONS.setdefault(int(cid), "Shared by someone else")
                COLLECTION_OWNERS[int(cid)] = owner
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
        if p.startswith("koreader/") and p not in ("koreader/credentials", "koreader/plugin-package"):
            if not self.ko_user():
                return
            STATE["seen"].append([method, p])
            return self.koreader(method, p[len("koreader/"):], q)
        m = re.match(r"^epub/(\d+)/info$", p)
        if m and method == "GET":
            # the reader's list of what's in the EPUB, with sizes (a narrated book: its audio and SMIL too)
            if not self.api_key():
                return
            bid = int(m.group(1))
            b = BOOKS.get(bid) if isinstance(BOOKS, dict) else next((x for x in BOOKS if x["id"] == bid), None)
            if not b:
                return self.error(404, "Book not found")
            manifest = [{"id": "ch1", "href": "OEBPS/ch1.xhtml", "mediaType": "application/xhtml+xml", "size": len(b["data"])}]
            if bid in NARRATED:
                extra = len(narrated_data(b)) - len(b["data"])
                manifest += [{"id": "a1", "href": "OEBPS/audio/1.mp3", "mediaType": "audio/mpeg", "size": extra - 300},
                             {"id": "s1", "href": "OEBPS/ch1.smil", "mediaType": "application/smil+xml", "size": 300}]
            return self.send(200, {"spine": [], "manifest": manifest, "toc": []})
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
            if not isinstance(pg, dict) or not isinstance(pg.get("page"), int) or not isinstance(pg.get("size"), int) or pg["page"] < 0 \
                    or not isinstance(d.get("sort"), list):
                return self.error(400, "sort and pagination are required")
            rules = (d.get("filter") or {}).get("rules") or []
            fmts = {str(v).lower() for r in rules if r.get("field") == "format" and r.get("operator") == "includesAny"
                    for v in r.get("value") or []}
            genres = {str(v) for r in rules if r.get("field") == "genre" and r.get("operator") == "includesAny"
                      for v in r.get("value") or []}
            if "q" in d and not isinstance(d["q"], str):
                return self.error(400, "q must be a string")
            found = []
            # (the books, then the audiobooks: each as the main API's card)
            cards = [(b["format"], b.get("genres") or [], b["title"] + " " + " ".join(b["authors"]), ebook_card(b)) for b in BOOKS]
            cards += [(a["format"], ab.get("genres") or [], ab["title"] + " " + " ".join(ab["authors"]), audio_card(ab))
                      for ab in AUDIOBOOKS.values() for a in ab["assets"][:1]]
            for fmt, gs, text, card in sorted(cards, key=lambda c: c[3]["title"].lower()):
                if rules and fmts and fmt not in fmts:
                    continue
                if genres and not genres & set(gs):
                    continue
                if d.get("q") and d["q"].lower() not in text.lower():
                    continue
                found.append(card)
            if d["sort"] and isinstance(d["sort"][0], dict) and d["sort"][0].get("dir") == "desc":
                found.reverse()
            items = found[pg["page"] * pg["size"]:(pg["page"] + 1) * pg["size"]]  # (pages from 0, as the real one)
            return self.send(201, {"items": items, "total": len(found), "page": pg["page"], "size": pg["size"]})
        m = re.match(r"^dashboard/scrollers/([a-z-]+)$", p)
        if m and method == "GET":
            # The web dashboard's shelves. Only "continue-listening" here: audiobooks with a saved
            # position short of the end, the one listened to last first. Its cards carry no time.
            if not self.api_key():
                return
            if m.group(1) != "continue-listening":
                return self.error(400, "Validation failed (enum string is expected)")
            limit = q.get("limit", "20")
            if not limit.isdigit() or not 1 <= int(limit) <= 50:
                return self.error(400, "limit must be between 1 and 50")
            STATE["seen"].append([method, p])
            going = sorted(((st["capturedAt"], bid) for bid, st in STATE["playback"].items()
                            if bid in AUDIOBOOKS and 0 < st["percentage"] < 100), reverse=True)
            return self.send(200, {"books": [audio_card(AUDIOBOOKS[bid]) for _at, bid in going[:int(limit)]],
                                   "total": len(going)})
        m = re.match(r"^books/(\d+)$", p)
        if m and method == "GET":
            # the main API's book page (only what GZreader reads: the community ratings)
            if not self.api_key():
                return
            b = next((b for b in BOOKS if b["id"] == int(m.group(1))), None)
            if not b:
                return self.error(404, "Book not found")
            return self.send(200, {"id": b["id"], "title": b["title"], "rating": None, "communityRatings": [
                {"provider": "goodreads", "rating": 4.05, "ratingCount": 2310, "updatedAt": None},
                {"provider": "hardcover", "rating": 3.9, "ratingCount": 40, "updatedAt": None}]})
        m = re.match(r"^books/(\d+)/thumbnail$", p)
        if m and method == "GET":
            if not self.api_key():
                return
            if int(m.group(1)) not in AUDIOBOOKS and not any(b["id"] == int(m.group(1)) for b in BOOKS):
                return self.error(404, "Book not found")
            return self.send(200, PNG, "image/png", {"ETag": '"1790000000000"'})
        # collections on the main API: your own and others' shared ones listed; only your own changed
        if p == "collections" and method == "GET":
            if not self.api_key():
                return
            STATE["seen"].append([method, p])
            return self.send(200, [{"id": i, "name": n, "userId": COLLECTION_OWNERS.get(i, 1),
                                    "bookCount": sum(i in b["collections"] for b in BOOKS)} for i, n in COLLECTIONS.items()])
        m = re.match(r"^collections/(\d+)/books$", p)
        if m and method in ("POST", "DELETE"):
            if not self.api_key(write=True):
                return
            STATE["seen"].append([method, p])
            cid = int(m.group(1))
            if cid not in COLLECTIONS:
                return self.error(404, "Collection not found")
            if COLLECTION_OWNERS.get(cid, 1) != 1:
                return self.error(403, "You cannot edit this collection")
            d = self.body()
            ids = isinstance(d, dict) and d.get("bookIds")
            if not isinstance(ids, list) or not ids or not all(isinstance(i, int) and not isinstance(i, bool) for i in ids) or set(d) - {"bookIds", "query"}:
                return self.error(400, "bookIds must be a non-empty array of book ids")
            changed = 0
            for b in BOOKS:
                if b["id"] in ids:
                    if method == "POST" and cid not in b["collections"]:
                        b["collections"].append(cid); changed += 1
                    if method == "DELETE" and cid in b["collections"]:
                        b["collections"].remove(cid); changed += 1
            return self.send(200 if method == "DELETE" else 201, {"changed": changed})
        # the KOReader sync sign-in, managed with the API key (its "KOReader sync" permission)
        if p in ("koreader/credentials", "koreader/plugin-package"):
            if not self.api_key(write=method != "GET"):
                return
            STATE["seen"].append([method, p])
            if not STATE["key_ko_permission"]:
                return self.error(403, "Forbidden resource")
            made = STATE["ko_made"]
            has = STATE["ko_credentials"] or made
            name = made["username"] if made else KO_USER
            if p == "koreader/credentials" and method == "GET":
                if not has:
                    return self.send(200, b"", "application/json")
                return self.send(200, {"username": name, "syncEnabled": STATE["sync_enabled"], "hideAudioOnlyBooks": True,
                                       "createdAt": "2026-10-01T08:00:00.000Z", "readAloudDelivery": STATE["ko_delivery"]})
            if p == "koreader/credentials" and method == "POST":
                d = self.body()
                if (not isinstance(d, dict) or set(d) - {"username", "password", "readAloudDelivery"} or not isinstance(d.get("username"), str)
                        or not 3 <= len(d["username"]) <= 100 or not isinstance(d.get("password"), str) or not 6 <= len(d["password"]) <= 128):
                    return self.error(400, "Bad Request")
                if has:
                    return self.error(409, "KOReader credentials already exist")
                if d["username"] in STATE["ko_names_taken"]:
                    return self.error(409, "Username already taken")
                if d.get("readAloudDelivery") not in (None, "original", "audioless_epub"):
                    return self.error(400, "Bad Request")
                STATE["ko_delivery"] = d.get("readAloudDelivery")  # (none sent: the default, Automatic)
                STATE["ko_made"] = {"username": d["username"], "md5": hashlib.md5(d["password"].encode()).hexdigest()}
                return self.send(201, {"success": True})
            if p == "koreader/plugin-package" and method == "GET":
                origin = q.get("origin", "")
                if not re.match(r"^https?://[^/]+", origin):
                    return self.error(400, "origin must be a valid http(s) URL")
                if not has:
                    return self.error(404, "Create KOReader sync credentials first")
                if not STATE["ko_md5_known"]:
                    return self.error(400, "Update your KOReader password once to enable the preconfigured download")
                key = made["md5"] if made else KO_KEY
                buf = io.BytesIO()
                with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
                    z.writestr("bookorbit.koplugin/bookorbit_provision.lua",
                               "-- (a stand-in for the sign-in file a real server puts in its plugin download)\nreturn {\n"
                               '    server_url = "%s",\n    username = "%s",\n    userkey = "%s",\n    generated_at = "2026-11-22T10:00:00.000Z",\n}\n'
                               % (origin, name, key))
                    z.writestr("bookorbit.koplugin/_meta.lua", 'return { name = "bookorbit" }\n')
                    z.writestr("bookorbit.koplugin/main.lua", "-- (the plugin itself: not GZreader's to read)\n" * 400)
                return self.send(200, buf.getvalue(), "application/zip", {"Cache-Control": "no-store"})
            return self.error(404, "Not Found")
        # book requests: ask for a book the server doesn't have; your own listed, newest first
        if p == "book-requests" or p.startswith("book-requests/"):
            if not self.api_key(write=method != "GET"):
                return
            STATE["seen"].append([method, p])
            if not STATE["request_permission"]:
                return self.error(403, "Forbidden resource")
            return self.book_requests(method, p[len("book-requests"):].lstrip("/"), q)
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
        if p in ("plugin/annotations/exchange", "plugin/annotations/exchange-ack") and method == "POST":
            d = self.body()
            if not self.device(d):
                return
            books = d.get("books")
            if not isinstance(books, list) or not 1 <= len(books) <= 20:
                return self.error(400, "books must hold 1 to 20 books")
            ack = p.endswith("-ack")
            results, unmatched = [], []
            for book in books:
                bad = check_ack_book(book) if ack else check_exchange_book(book)
                if bad:
                    return self.error(400, bad)
                b = next((b for b in BOOKS if b["hash"] == book["hash"].lower()), None)
                if not b:
                    unmatched.append(book["hash"].lower())
                    continue
                results.append((ack_book if ack else exchange_book)(d["deviceId"], b, book))
            return self.send(201, {"results": results, "unmatched": unmatched, "positionIncompatible": []})
        if p == "plugin/page-stats" and method == "POST":
            d = self.body()
            if not self.device(d):
                return
            books = d.get("books")
            if not isinstance(books, list) or not 1 <= len(books) <= 50:
                return self.error(400, "books must hold 1 to 50 books")
            results, unmatched = [], []
            whole = lambda v: isinstance(v, int) and not isinstance(v, bool)
            for book in books:
                if not isinstance(book, dict) or not isinstance(book.get("hash"), str) or not MD5.match(book["hash"]):
                    return self.error(400, "hash must be an MD5 hex string")
                events = book.get("events")
                if not isinstance(events, list) or not events:
                    return self.error(400, "events must not be empty")
                for e in events:
                    if not isinstance(e, dict) or not (whole(e.get("page")) and e["page"] >= 0 and whole(e.get("startTime")) and e["startTime"] >= 1
                                                       and whole(e.get("durationSeconds")) and 0 <= e["durationSeconds"] <= 86400
                                                       and whole(e.get("totalPages")) and e["totalPages"] >= 1) or set(e) - {"page", "startTime", "durationSeconds", "totalPages"}:
                        return self.error(400, "each event needs page, startTime, durationSeconds (0 to 86400) and totalPages, as whole numbers")
                h = book["hash"].lower()
                if not any(b["hash"] == h for b in BOOKS):
                    unmatched.append(h)
                    continue
                rows = STATE["page_stats"].setdefault(h, [])
                accepted = 0
                for e in events:
                    if not any(r[0] == e["page"] and r[1] == e["startTime"] for r in rows):
                        rows.append([e["page"], e["startTime"], e["durationSeconds"], e["totalPages"]])
                        accepted += 1
                results.append({"hash": h, "accepted": accepted, "duplicates": len(events) - accepted})
            return self.send(201, {"results": results, "unmatched": unmatched})
        m = re.match(r"^plugin/catalog/books/(\d+)/rating$", p)
        if m and method == "PUT":
            d = self.body()
            if not any(b["id"] == int(m.group(1)) for b in BOOKS):
                return self.error(404, "Book not found")
            r = isinstance(d, dict) and d.get("rating")
            if r is not None and not (isinstance(r, (int, float)) and not isinstance(r, bool) and 0 <= r <= 5):
                return self.error(400, "rating must be a number from 0 to 5")
            if isinstance(d, dict) and set(d) - {"rating"}:
                return self.error(400, "property %s should not exist" % sorted(set(d) - {"rating"})[0])
            STATE["ratings"][m.group(1)] = r
            return self.send(200, {"rating": r})
        if p in ("plugin/bookmarks/exchange", "plugin/bookmarks/exchange-ack") and method == "POST":
            d = self.body()
            if not self.device(d):
                return
            books = d.get("books")
            if not isinstance(books, list) or not 1 <= len(books) <= 20:
                return self.error(400, "books must hold 1 to 20 books")
            ack = p.endswith("-ack")
            results, unmatched = [], []
            for book in books:
                bad = check_mark_ack(book) if ack else check_mark_book(book)
                if bad:
                    return self.error(400, bad)
                b = next((b for b in BOOKS if b["hash"] == book["hash"].lower()), None)
                if not b:
                    unmatched.append(book["hash"].lower())
                    continue
                results.append((mark_ack if ack else mark_exchange)(d["deviceId"], b, book))
            return self.send(201, {"results": results, "unmatched": unmatched, "positionIncompatible": []})
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
        if p == "dashboard":
            # The reader's own numbers, over every device. Minutes per day for 371 days ending today
            # (k days ago: nothing every fifth day, else a number under 75; today 25).
            if q.get("section") not in (None, "random", "recently-added", "want-to-read", "up-next-in-series", "smart-scope"):
                return self.error(400, "Bad Request")
            today = time.strftime("%Y-%m-%d")
            minutes = [(0 if k % 5 == 1 else 25 if k == 0 else (k * 13) % 75) for k in range(370, -1, -1)]
            start = time.strftime("%Y-%m-%d", time.localtime(time.time() - 370 * 86400))
            streak = 0
            for m in reversed(minutes):
                if m <= 0:
                    break
                streak += 1
            shown = [list_item(b) for b in BOOKS]
            out = {"generatedAt": today + "T10:00:00.000Z", "username": "will", "displayName": "Will", "totalBooks": len(shown),
                   "browseCounts": {"inProgress": 2, "libraries": 2, "authors": 4, "series": 1, "collections": 2, "smartScopes": 0},
                   "sections": [], "continueReading": shown[:2], "discover": [] if q.get("section") else shown[:3],
                   "readingGoal": {"goalBooks": STATE["goal_books"], "completedBooks": 12, "year": int(today[:4])},
                   "readingStreak": {"currentStreak": streak, "longestStreak": 21, "lastSevenDays": [m > 0 for m in minutes[-7:]]},
                   "highlightOfTheDay": {"text": "The tide does not ask the shore for leave.", "note": None, "bookTitle": shown[0]["title"],
                                         "bookId": shown[0]["id"], "hasCover": True, "chapterTitle": "Chapter 3", "createdAt": today + "T08:00:00.000Z"},
                   "yearAgo": {"book": shown[1], "minutes": 312, "days": 9, "endProgress": 100, "firstDay": "2025-11-10", "lastDay": "2025-12-02"},
                   "finishedThisYear": shown[:3],
                   "achievements": {"earned": 5, "total": 40,
                                    "next": {"key": "hours_read_50", "groupKey": "hours_read", "name": "Fifty hours", "description": "Read for fifty hours.",
                                             "rarity": "common", "iconName": "clock", "threshold": 50, "currentProgress": 41, "awardedAt": None},
                                    "latest": {"key": "books_finished_10", "groupKey": "books_finished", "name": "Ten down", "description": "Finish ten books.",
                                               "rarity": "common", "iconName": "book", "threshold": 10, "currentProgress": 10,
                                               "awardedAt": today + "T09:00:00.000Z"}} if STATE["achievements"] else None}
            if STATE["reading_year"]:
                out["readingYear"] = {"startDate": start, "minutes": minutes}
            return self.send(200, out)
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
            return self.send(200, detail(b, q.get("variant"))) if b else self.error(404, "Book not found")
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
            variant = q.get("variant")
            STATE["last_download_variant"] = variant
            if b["id"] in NARRATED and variant == "original":
                return self.send(200, narrated_data(b), "application/epub+zip")
            if b["id"] in NARRATED and variant == "audioless_epub":
                STATE["audioless_made"] = True
            return self.send(200, b["data"], "application/epub+zip" if b["format"] == "epub" else "application/pdf",
                             {"Content-Disposition": 'attachment; filename="%s.%s"' % (b["title"], b["format"])})
        return self.error(404, "Not Found")

    # Main API: audiobooks ------------------------------------------------------
    def book_requests(self, method, p, q):
        def item(r):
            return {"id": r["id"], "userId": r["userId"], "requesterUsername": "will" if r["userId"] == 1 else "someone",
                    "mediaKind": r["mediaKind"], "status": r["status"], "title": r["title"], "subtitle": None,
                    "authors": r["authors"], "statusReason": r.get("statusReason"), "decisionNote": r.get("decisionNote"),
                    "matchedBookId": r.get("matchedBookId"), "createdAt": "2026-11-%02dT08:00:00.000Z" % (r["id"] % 27 + 1)}
        mine = [r for r in STATE["requests"] if r["userId"] == 1 or 1 in r.get("subscribers", [])]
        if p == "" and method == "POST":
            d = self.body()
            allowed = {"title", "subtitle", "authors", "mediaKind", "note", "seriesName", "seriesIndex", "isbn10", "isbn13", "publishedYear", "language"}
            if (not isinstance(d, dict) or set(d) - allowed or not isinstance(d.get("title"), str) or not d["title"].strip() or len(d["title"]) > 500
                    or d.get("mediaKind") not in ("ebook", "audiobook")
                    or ("authors" in d and (not isinstance(d["authors"], list) or not all(isinstance(a, str) for a in d["authors"])))):
                return self.error(400, "Bad Request")
            for r in STATE["requests"]:
                if r["title"].lower() == d["title"].strip().lower() and r["mediaKind"] == d["mediaKind"] and r["status"] not in ("cancelled", "rejected"):
                    if r["userId"] != 1 and 1 not in r.setdefault("subscribers", []):
                        r["subscribers"].append(1)
                    return self.send(201, {"request": item(r), "subscribed": r["userId"] != 1})
            r = {"id": 500 + len(STATE["requests"]) + 1, "userId": 1, "title": d["title"].strip(), "authors": d.get("authors") or [],
                 "mediaKind": d["mediaKind"], "status": STATE["request_status"]}
            STATE["requests"].append(r)
            return self.send(201, {"request": item(r), "subscribed": False})
        if p == "" and method == "GET":
            try:
                page, limit = int(q.get("page", "1")), int(q.get("limit", "20"))
            except ValueError:
                return self.error(400, "Bad Request")
            if page < 1 or limit < 1 or limit > 100:
                return self.error(400, "Bad Request")
            rows = sorted(mine, key=lambda r: -r["id"])
            return self.send(200, {"items": [item(r) for r in rows[(page - 1) * limit:page * limit]], "total": len(rows)})
        m = re.match(r"^(\d+)/cancel$", p)
        if m and method == "POST":
            for r in STATE["requests"]:
                if r["id"] == int(m.group(1)):
                    if r["userId"] != 1:
                        return self.error(403, "You cannot cancel this book request")
                    if r["status"] in ("cancelled", "rejected", "available"):
                        return self.error(400, "This request can no longer be cancelled")
                    r["status"] = "cancelled"
                    return self.send(200, item(r))
            return self.error(404, "Book request not found")
        m = re.match(r"^(\d+)$", p)
        if m and method == "GET":
            for r in mine:
                if r["id"] == int(m.group(1)):
                    return self.send(200, item(r))
            return self.error(404, "Book request not found")
        return self.error(404, "Not Found")

    def audiobooks(self, method, p):
        m = re.match(r"^(\d+)/(.+)$", p)
        ab = m and AUDIOBOOKS.get(int(m.group(1)))
        if not ab:
            return self.error(404, "Book has no audiobook assets")
        rest, bid = m.group(2), ab["id"]
        if rest == "manifest" and method == "GET":
            assets = [{"assetId": a["assetId"], "fileId": a["fileId"], "sequence": a["sequence"], "format": a["format"],
                       "durationMs": a["durationMs"], "sizeBytes": len(a["data"]),
                       "etag": hashlib.md5(a["data"]).hexdigest()} for a in ab["assets"]]
            chapters, at = [], 0
            for a in ab["assets"]:
                if "chapters" not in ab:
                    chapters.append({"id": "ch-%d" % a["sequence"], "title": "Part %d" % (a["sequence"] + 1), "assetId": a["assetId"],
                                     "sequence": a["sequence"], "startMs": at, "endMs": at + a["durationMs"], "assetOffsetMs": 0})
                at += a["durationMs"]
            for n, (title, start, end) in enumerate(ab.get("chapters", [])):
                chapters.append({"id": "ch-%d" % n, "title": title, "assetId": ab["assets"][0]["assetId"], "sequence": n,
                                 "startMs": start, "endMs": end, "assetOffsetMs": start})
            return self.send(200, {"schema": "bookorbit.audiobook-manifest", "schemaVersion": 2, "revision": manifest_revision(ab),
                                   "book": {"id": bid, "title": ab["title"], "authors": ab["authors"],
                                            "narrators": ab["narrators"], "hasCover": True},
                                   "assets": assets, "chapters": chapters, "totalDurationMs": at})
        m = re.match(r"^assets/([^/]+)/content$", rest)
        if m and method == "GET":
            a = next((a for a in ab["assets"] if a["assetId"] == m.group(1)), None)
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
                if d["manifestRevision"] != manifest_revision(ab):
                    return self.error(412, "Audiobook manifest has changed")
                a = next((a for a in ab["assets"] if a["assetId"] == d["assetId"]), None)
                if not a:
                    return self.error(400, "assetId does not belong to this audiobook")
                if cur and cur.get("operationId") == d["operationId"]:
                    return self.send(200, {k: v for k, v in cur.items() if k != "operationId"})  # a resend: no change
                if d["positionMs"] > a["durationMs"] + 1000:
                    return self.error(400, "positionMs exceeds the asset duration")
                if d["baseRevision"] != (cur["revision"] if cur else 0):
                    return self.error(409, "Playback state revision conflict")
                pos = min(d["positionMs"], a["durationMs"])
                total = sum(x["durationMs"] for x in ab["assets"])
                before = sum(x["durationMs"] for x in ab["assets"] if x["sequence"] < a["sequence"])
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
