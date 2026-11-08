"""Mock Grimmory server mirroring the endpoints the Kindle plugin uses.

Behaviour copied from grimmory backend source: rotating refresh tokens,
KOReader user upsert (stores md5 of password), 404 when no KOReader user,
app book pagination shape, Bearer-protected download.
"""
import base64, os, hashlib, json, re, secrets, sys, threading, time
from urllib.parse import urlencode
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

USERS = {"will": "hunter22"}
STATE = {
    "access": {},          # token -> user
    "refresh": {},         # token -> user
    "kouser": {},          # user -> dict
    "sync_perm": True,
    "log": [],
    "expire_next_access": False,
    "progress": {},        # book_id -> file progress (mirrors UserBookFileProgressEntity)
    "ratings": {},         # book_id -> personalRating (1-10, UserBookProgressEntity)
    "sessions": [],
    "offline": False,      # simulate unreachable progress endpoints
    "oidc_enabled": True,
    "oidc_force_only": False,
    "oidc_states": set(),  # issued by /oidc/state, consumed on exchange
    "idp_codes": {},       # code -> {challenge, redirect_uri, nonce}
    "idp_strict": False,   # True: no extra redirect URIs registered at the IdP
    "idp_deny": False,     # simulate the user cancelling at the IdP
    "dl_big": False,       # 2 MB book
    "dl_slow": False,      # trickle the download
    "dl_stall": False,     # send part of the body, then hang
    "refresh_calls": 0,
    "lib500": False,
    "old_search": False,   # an older Grimmory whose book list ignores search=
    "cr_paused": False,    # /continue-reading empty; the books are Paused (the web still lists them)
    "bookmarks": {},       # id -> BookMark dto
    "bm_next": 500,
    "annotations": {},     # id -> AnnotationResponse
    "an_next": 900,
    "an_lose_reply": False, # create, then drop the connection (reply lost)
}
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 0
BOOKS = [
    {"id": i, "title": f"Book {i:02d}", "authors": ["Author"], "primaryFileType": t,
     # (an audiobook in one file is named as on disk, an M4B; book 32 is folder-based)
     "primaryFileName": f"book{i}.m4b" if t == "AUDIOBOOK" and i != 32 else f"book{i}.{t.lower()}", "fileSizeKb": 300, "readProgress": 12.5 if i == 1 else None,
     "primaryFileId": 1000 + i}
    for i, t in enumerate(["EPUB"] * 30 + ["AUDIOBOOK"] * 3 + ["PDF"] * 2, start=1)
]
SHELVES = {4: [10, 11, 12], 6: [], 7: [3], 8: []}
# the regular shelves (ShelfEntity): yours (user 1) and someone else's (user 2):
# 7 is public (you see it, can't put books on it), 8 private (you never see it)
SHELF_INFO = {4: {"name": "Kindle", "userId": 1, "publicShelf": False},
              6: {"name": "Beach reads", "userId": 1, "publicShelf": False},
              7: {"name": "Club picks", "userId": 2, "publicShelf": True},
              8: {"name": "Not yours", "userId": 2, "publicShelf": False}}


def shelf_dto(sid):  # ShelfMapper.toShelf
    i = SHELF_INFO[sid]
    return {"id": sid, "name": i["name"], "userId": i["userId"], "publicShelf": i["publicShelf"], "bookCount": len(SHELVES[sid])}


def shelves_of(bid, me=1):  # BookUtils.filterShelvesByUserId: public ones or yours
    return [shelf_dto(sid) for sid in sorted(SHELVES) if bid in SHELVES[sid]
            and (SHELF_INFO[sid]["publicShelf"] or SHELF_INFO[sid]["userId"] == me)]
SUBTITLES = {3: "Old School", 2: "Rodrick Rules"}
DESCRIPTIONS = {32: "<p>A <b>folder</b> audiobook &amp; its tracks.</p><p>Second paragraph.</p>"}
BOOK_BYTES = b"PK\x03\x04 fake epub bytes " * 200
AUDIO_BYTES = b"ID3 fake audio " * 400
COVER_JPEG = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "media", "cover.jpg"), "rb").read()  # a real one (the sync page shrinks it)
M4A_BYTES = open(os.environ["GZ_TEST_M4A"], "rb").read() if os.environ.get("GZ_TEST_M4A") else b""
# libraries / authors / series metadata for the browser
for b in BOOKS:
    i = b["id"]
    b["libraryId"] = 1 if i % 2 else 2
    b["authors"] = [f"Author {i % 3}"]
    if i in (5, 6, 7):
        b["seriesName"], b["seriesNumber"] = "Saga / Part One", {5: 2.0, 6: 1.0, 7: 2.5}[i]
    if i == 31:   # an audiobook in the same series: must be filtered out on the Kindle
        b["seriesName"], b["seriesNumber"] = "Saga / Part One", 3.0
    if i in (32, 33):   # audiobook-only author, series and library
        b["authors"], b["seriesName"], b["seriesNumber"], b["libraryId"] = ["Audio Author"], "Audio Only Saga", float(i), 3
LIBRARIES = [{"id": 2, "name": "fiction", "bookCount": 17}, {"id": 1, "name": "Comics", "bookCount": 18},
             {"id": 3, "name": "Audiobooks", "bookCount": 2}]
AUTHORS = [{"id": 100 + k, "name": f"Author {k}", "bookCount": 12, "hasPhoto": False} for k in range(60)]
SERIES = [{"seriesName": "Saga / Part One", "bookCount": 3, "seriesTotal": 5, "authors": ["Author 2"]},
          {"seriesName": "Another", "bookCount": 1, "seriesTotal": None, "authors": []}]


def page_of(items, q, default_size):
    page, size = int(q.get("page", ["0"])[0]), int(q.get("size", [str(default_size)])[0])
    chunk = items[page * size:(page + 1) * size]
    total_pages = max(1, -(-len(items) // size))
    return {"content": chunk, "page": page, "size": size, "totalElements": len(items),
            "totalPages": total_pages, "hasNext": page + 1 < total_pages, "hasPrevious": page > 0}


ALLOW_HEADERS = 'Authorization, Cache-Control, Content-Type, Range, If-None-Match, If-Modified-Since'


class H(BaseHTTPRequestHandler):

    # (the sync page, docs/sync, asks from a browser: cross-origin, like the real server)
    def end_headers(self):
        o = self.headers.get("Origin")
        # (like Grimmory: its /api/v1/media/** chain has no CORS, so a web
        # page can show those covers in <img> but not read them)
        if o and not self.path.startswith("/api/v1/media/"):
            self.send_header("Access-Control-Allow-Origin", o)
            self.send_header("Access-Control-Allow-Credentials", "true")
            self.send_header("Access-Control-Expose-Headers", "Content-Disposition, Accept-Ranges, Content-Range, Content-Length")
        super().end_headers()

    def do_OPTIONS(self):
        if self.path.startswith("/api/v1/media/"):
            self.send_response(200); self.send_header("Allow", "GET,HEAD,OPTIONS"); self.send_header("Content-Length", "0")
            return self.end_headers()
        self.send_response(204)
        self.send_header("Access-Control-Allow-Methods", "GET, HEAD, POST, PUT, DELETE, OPTIONS, PATCH, REPORT, PROPFIND")
        self.send_header("Access-Control-Allow-Headers", ALLOW_HEADERS or (self.headers.get("Access-Control-Request-Headers") or ""))
        self.send_header("Content-Length", "0")
        self.end_headers()

    def log_message(self, *a):
        pass

    def _json(self, code, obj=None):
        body = b"" if obj is None else json.dumps(obj).encode()
        self.send_response(code)
        if len(body) >= 1024 and "gzip" in (self.headers.get("Accept-Encoding") or ""):  # like Spring's server.compression
            import gzip as _gz
            body = _gz.compress(body)
            self.send_header("Content-Encoding", "gzip")
            STATE["gzip_replies"] = STATE.get("gzip_replies", 0) + 1
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return json.loads(self.rfile.read(n) or b"{}") if n else {}

    def _user(self):
        auth = self.headers.get("Authorization", "")
        tok = auth[7:] if auth.startswith("Bearer ") else None
        if not tok and urlparse(self.path).path.startswith(("/api/v1/media/", "/api/v1/audiobooks/")):
            tok = parse_qs(urlparse(self.path).query).get("token", [None])[0]   # (QueryParameterJwtFilter)
        if STATE["expire_next_access"] and tok:
            STATE["expire_next_access"] = False
            STATE["access"].pop(tok, None)
        return STATE["access"].get(tok)

    def _tokens(self, user):
        a, r = secrets.token_hex(8), secrets.token_hex(8)
        STATE["access"][a] = user
        STATE["refresh"][r] = user
        return {"accessToken": a, "refreshToken": r, "expires": 7200}

    def do_DELETE(self):
        u = urlparse(self.path)
        STATE["log"].append(("DELETE", u.path))
        if not self._user():
            return self._json(401)
        if u.path.startswith("/api/v1/annotations/"):
            aid = int(u.path.rsplit("/", 1)[1])
            if STATE["annotations"].pop(aid, None) is None:
                return self._json(404)
            return self._json(204)
        if u.path.startswith("/api/v1/bookmarks/"):
            bid = int(u.path.rsplit("/", 1)[1])
            if STATE["bookmarks"].pop(bid, None) is None:
                return self._json(404)
            return self._json(204)
        return self._json(404)

    def do_POST(self):
        u = urlparse(self.path)
        STATE["log"].append(("POST", u.path))
        if u.path == "/api/application/batch":   # Tianji application tracking
            b = self._body()
            STATE.setdefault("usage", []).extend(b.get("events", []))
            return self._json(200, {"ok": True})
        if u.path == "/api/v1/annotations":
            if not self._user():
                return self._json(401)
            b = self._body()
            if not b.get("text") or not b.get("cfi") or len(b["cfi"]) > 1000:
                return self._json(400, {"message": "invalid"})
            for a in STATE["annotations"].values():
                if a["bookId"] == b.get("bookId") and a["cfi"] == b["cfi"]:
                    return self._json(409, {"message": "Annotation already exists"})
            STATE["an_next"] += 1
            now = "2026-10-29T10:00:%02d" % (STATE["an_next"] % 60)
            a = {"id": STATE["an_next"], "bookId": b.get("bookId"), "cfi": b["cfi"], "text": b["text"],
                 "color": b.get("color") or "#FFC107", "style": b.get("style") or "highlight", "note": b.get("note"),
                 "chapterTitle": b.get("chapterTitle"), "createdAt": now, "updatedAt": now}
            STATE["annotations"][a["id"]] = a
            if STATE["an_lose_reply"]:
                STATE["an_lose_reply"] = False
                self.close_connection = True
                return
            return self._json(200, a)
        if u.path == "/api/v1/bookmarks":
            if not self._user():
                return self._json(401)
            b = self._body()
            for bm in STATE["bookmarks"].values():
                if bm["bookId"] == b.get("bookId") and ((b.get("cfi") and bm.get("cfi") == b.get("cfi")) or (b.get("pageNumber") and bm.get("pageNumber") == b.get("pageNumber"))):
                    return self._json(409, {"message": "Bookmark already exists"})
            STATE["bm_next"] += 1
            bm = {"id": STATE["bm_next"], "bookId": b.get("bookId"), "cfi": b.get("cfi"), "pageNumber": b.get("pageNumber"), "title": b.get("title")}
            STATE["bookmarks"][bm["id"]] = bm
            return self._json(200, bm)
        if u.path == "/api/v1/auth/login":
            b = self._body()
            if USERS.get(b.get("username")) == b.get("password"):
                return self._json(200, self._tokens(b["username"]))
            return self._json(401, {"message": "Invalid credentials"})
        if u.path == "/api/v1/auth/refresh":
            STATE["refresh_calls"] += 1
            b = self._body()
            user = STATE["refresh"].pop(b.get("refreshToken"), None)  # rotation
            if not user:
                return self._json(401, {"message": "Invalid or expired refresh token"})
            return self._json(200, self._tokens(user))
        if u.path == "/api/v1/auth/oidc/mobile/callback":
            n = int(self.headers.get("Content-Length") or 0)
            form = {k: v[0] for k, v in parse_qs(self.rfile.read(n).decode()).items()}
            for k in ("code", "code_verifier", "redirect_uri", "nonce", "state"):
                if k not in form:
                    return self._json(400, {"message": "missing " + k})
            if form["state"] not in STATE["oidc_states"]:
                return self._json(401, {"message": "Invalid OIDC state"})
            STATE["oidc_states"].discard(form["state"])          # validateAndConsume
            ru = urlparse(form["redirect_uri"])
            if ru.scheme not in ("http", "https") or not ru.path.endswith("/oauth2-callback"):
                return self._json(400, {"message": "Invalid redirect URI"})
            redirect_origin = f"{ru.scheme}://{ru.hostname}" + (f":{ru.port}" if ru.port not in (None, 80, 443) else "")
            origin = (self.headers.get("Origin") or "").rstrip("/") or f"http://127.0.0.1:{PORT}"
            if origin != redirect_origin:
                return self._json(400, {"message": "Invalid redirect URI (origin mismatch)"})
            c = STATE["idp_codes"].pop(form["code"], None)
            if not c or c["redirect_uri"] != form["redirect_uri"] or c["nonce"] != form["nonce"]:
                return self._json(401, {"message": "invalid_grant"})
            chal = base64.urlsafe_b64encode(hashlib.sha256(form["code_verifier"].encode()).digest()).decode().rstrip("=")
            if chal != c["challenge"]:
                return self._json(401, {"message": "PKCE verification failed"})
            STATE["last_oidc_origin"] = origin
            return self._json(200, self._tokens("will"))
        if u.path == "/api/v1/reading-sessions":
            if STATE["offline"] or not self._user():
                return self._json(503 if STATE["offline"] else 401)
            b = self._body()
            for k in ("bookId", "startTime", "endTime", "durationSeconds"):
                if b.get(k) is None:
                    return self._json(400, {"missing": k})
            STATE["sessions"].append(b)
            return self._json(200)
        if u.path == "/api/v1/auth/logout":
            self._body()
            return self._json(200, {})
        if u.path == "/api/v1/books/shelves":  # BookController.addBookToShelf -> BookUpdateService.assignShelvesToBooks
            if not self._user():
                return self._json(401)
            if STATE["offline"]:
                return self._json(503)
            b = self._body()
            STATE["last_shelves_body"] = b
            add, rem = b.get("shelvesToAssign"), b.get("shelvesToUnassign")
            if not isinstance(b.get("bookIds"), list) or not isinstance(add, list) or not isinstance(rem, list):
                return self._json(400, {"message": "bookIds, shelvesToAssign and shelvesToUnassign must be lists"})
            if any(SHELF_INFO.get(int(x), {}).get("userId") != 1 for x in add + rem):   # validateShelfOwnership
                return self._json(403, {"message": "Cannot assign shelves that do not belong to the user."})
            for bid in (int(x) for x in b["bookIds"]):
                for sid in rem:
                    if bid in SHELVES[int(sid)]: SHELVES[int(sid)].remove(bid)
                for sid in add:
                    if bid not in SHELVES[int(sid)]: SHELVES[int(sid)].append(bid)
            return self._json(200, [{"id": int(x), "shelves": shelves_of(int(x))} for x in b["bookIds"]])
        if u.path == "/api/v1/books/reset-personal-rating":  # BookController.resetPersonalRating
            if STATE["offline"]:
                return self._json(503)
            ids = self._body()
            for bid in ids:
                STATE["ratings"].pop(int(bid), None)
            return self._json(200, [{"bookId": bid, "personalRating": None} for bid in ids])
        self._json(404)

    def do_PUT(self):
        u = urlparse(self.path)
        STATE["log"].append(("PUT", u.path))
        user = self._user()
        if not user:
            return self._json(401)
        if u.path.startswith("/api/v1/annotations/"):
            aid = int(u.path.rsplit("/", 1)[1])
            a = STATE["annotations"].get(aid)
            if not a:
                return self._json(404)
            b = self._body()
            for k in ("color", "style", "note"):
                if k in b and b[k] is not None:
                    a[k] = b[k]
            a["updatedAt"] = "2026-10-29T11:00:00"
            return self._json(200, a)
        if u.path.startswith("/api/v1/app/books/") and u.path.endswith("/progress"):
            if STATE["offline"]:
                return self._json(503)
            book_id = int(u.path.split("/")[5])
            b = self._body()
            if book_id > 500:   # (no such book: Grimmory's "not found")
                return self._json(404, {"message": "Book not found"})
            fp = b.get("fileProgress")
            if not fp or fp.get("bookFileId") is None or fp.get("progressPercent") is None:
                return self._json(400, {"message": "invalid"})
            # ReadingProgressService.saveToUserBookFileProgress: every field overwritten
            STATE["progress"][book_id] = {
                "bookFileId": fp["bookFileId"], "positionData": fp.get("positionData"),
                "positionHref": fp.get("positionHref"), "progressPercent": fp["progressPercent"],
                "contentSourceProgressPercent": fp.get("contentSourceProgressPercent"),
            }
            STATE["last_put_body"] = b
            return self._json(200)
        if u.path == "/api/v1/books/personal-rating":  # BookController.updatePersonalRating
            if STATE["offline"]:
                return self._json(503)
            b = self._body()
            if not isinstance(b.get("ids"), list) or not isinstance(b.get("rating"), int):
                return self._json(400, {"message": "invalid"})
            for bid in b["ids"]:
                STATE["ratings"][int(bid)] = b["rating"]
            return self._json(200, [{"bookId": bid, "personalRating": b["rating"]} for bid in b["ids"]])
        if u.path == "/api/v1/koreader-users/me":
            if not STATE["sync_perm"]:
                return self._json(403)
            b = self._body()
            ko = {"id": 1, "username": b["username"], "password": b["password"],
                  "passwordMD5": hashlib.md5(b["password"].encode()).hexdigest(), "syncEnabled": False}
            STATE["kouser"][user] = ko
            return self._json(200, ko)
        self._json(404)

    def do_PATCH(self):
        u = urlparse(self.path)
        STATE["log"].append(("PATCH", self.path))
        user = self._user()
        if not user:
            return self._json(401)
        if u.path == "/api/v1/koreader-users/me/sync":
            enabled = parse_qs(u.query).get("enabled") == ["true"]
            STATE["kouser"][user]["syncEnabled"] = enabled
            self.send_response(204); self.end_headers(); return
        self._json(404)

    def do_GET(self):
        u = urlparse(self.path)
        q = parse_qs(u.query)
        STATE["log"].append(("GET", self.path))
        base = f"http://127.0.0.1:{PORT}"
        if u.path == "/api/v1/public-settings":
            return self._json(200, {"oidcEnabled": STATE["oidc_enabled"], "remoteAuthEnabled": False,
                                    "oidcForceOnlyMode": STATE["oidc_force_only"],
                                    "oidcProviderDetails": {"providerName": "Authentik", "clientId": "grimmory",
                                                            "issuerUri": base + "/idp/", "scopes": "openid profile email offline_access"}})
        if u.path == "/api/v1/auth/oidc/state":
            st = secrets.token_hex(8); STATE["oidc_states"].add(st)
            return self._json(200, {"state": st})
        if u.path == "/idp/.well-known/openid-configuration":
            return self._json(200, {"issuer": base + "/idp/", "authorization_endpoint": base + "/idp/authorize?tenant=x"})
        if u.path == "/idp/authorize":
            ru = q.get("redirect_uri", [""])[0]
            registered = ru == "https://books.example.com/oauth2-callback" or (not STATE["idp_strict"] and ru.endswith("/oauth2-callback"))
            if q.get("tenant") != ["x"] or q.get("client_id") != ["grimmory"] or q.get("response_type") != ["code"] \
                    or q.get("code_challenge_method") != ["S256"] or not q.get("code_challenge") or not q.get("nonce"):
                return self._json(400, {"error": "invalid_request"})
            if not registered:
                body = b"<h1>Invalid redirect URI</h1>"
                self.send_response(400); self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body); return
            if STATE["idp_deny"]:
                loc = ru + "?" + urlencode({"error": "access_denied", "error_description": "User cancelled", "state": q["state"][0]})
            else:
                code = secrets.token_hex(8)
                STATE["idp_codes"][code] = {"challenge": q["code_challenge"][0], "redirect_uri": ru, "nonce": q["nonce"][0]}
                loc = ru + "?" + urlencode({"code": code, "state": q["state"][0]})
            self.send_response(302); self.send_header("Location", loc); self.send_header("Content-Length", "0"); self.end_headers(); return
        if u.path == "/api/koreader/users/auth":
            for ko in STATE["kouser"].values():
                if ko["username"] == self.headers.get("x-auth-user") and ko["passwordMD5"] == self.headers.get("x-auth-key"):
                    return self._json(200, {"authorized": "OK"})
            return self._json(401)
        user = self._user()
        if not user:
            return self._json(401)
        if u.path.startswith("/api/v1/annotations/book/"):
            bk = int(u.path.rsplit("/", 1)[1])
            return self._json(200, sorted([a for a in STATE["annotations"].values() if a["bookId"] == bk], key=lambda a: a["id"]))
        if u.path.startswith("/api/v1/bookmarks/book/"):
            if not self._user():
                return self._json(401)
            bk = int(u.path.rsplit("/", 1)[1])
            return self._json(200, [bm for bm in STATE["bookmarks"].values() if bm["bookId"] == bk])
        if u.path == "/api/v1/users/me":
            return self._json(200, {"id": 1, "username": user, "name": "Will"})
        if u.path == "/api/v1/koreader-users/me":
            if not STATE["sync_perm"]:
                return self._json(403)
            ko = STATE["kouser"].get(user)
            return self._json(200, ko) if ko else self._json(404, {"message": "Koreader user not found"})
        if u.path == "/api/v1/books/page":
            page = int(q.get("page", ["0"])[0]); size = int(q.get("size", ["20"])[0])
            chunk = BOOKS[page * size:(page + 1) * size]
            return self._json(200, {"content": [{"id": b["id"], "metadata": {"title": b["title"], "subtitle": SUBTITLES.get(b["id"])}} for b in chunk],
                                    "page": {"number": page, "size": size, "totalElements": len(BOOKS), "totalPages": -(-len(BOOKS) // size)}})
        parts = u.path.split("/")
        if len(parts) == 5 and u.path.startswith("/api/v1/books/") and parts[4].isdigit():
            if STATE["offline"]:
                return self._json(503)
            bid = int(parts[4])
            book = next((b for b in BOOKS if b["id"] == bid), None)
            if not book:
                return self._json(404)
            out = {"id": bid, "title": book["title"], "primaryFile": {"id": book["primaryFileId"]},
                   "metadata": {"title": book["title"], "subtitle": SUBTITLES.get(bid), "description": DESCRIPTIONS.get(bid)},
                   "personalRating": STATE["ratings"].get(bid), "shelves": shelves_of(bid)}
            fp = STATE["progress"].get(bid)
            if fp:  # ReadingProgressService.setBookProgressFromFileProgress (EPUB)
                if book["primaryFileType"] == "AUDIOBOOK":  # setBookProgressFromFileProgress (AUDIOBOOK)
                    out["audiobookProgress"] = {"positionMs": int(fp["positionData"]) if fp["positionData"] else None,
                                                "trackIndex": int(fp["positionHref"]) if fp["positionHref"] else None,
                                                "percentage": round(fp["progressPercent"], 1)}
                elif book["primaryFileType"] == "EPUB":
                    out["epubProgress"] = {"cfi": fp["positionData"], "href": fp["positionHref"],
                                           "contentSourceProgressPercent": fp["contentSourceProgressPercent"],
                                           "percentage": round(fp["progressPercent"], 1)}
                else:
                    out["pdfProgress"] = {"page": int(fp["positionData"]) if fp["positionData"] else None,
                                          "percentage": round(fp["progressPercent"], 1)}
            return self._json(200, out)
        if u.path.startswith("/api/v1/user-stats/reading/"):  # UserStatsController
            if not self._user():
                return self._json(401)
            if not STATE.get("stats_perm", True):
                return self._json(403)
            what = u.path.rsplit("/reading/", 1)[1]
            days = sorted({s["startTime"][:10] for s in STATE["sessions"]})
            if what == "streak":
                return self._json(200, {"currentStreak": STATE.get("streak", len(days) and 1), "longestStreak": STATE.get("longest", 5),
                                        "totalReadingDays": len(days), "last52Weeks": []})
            if what == "timeline":
                by_book = {}
                for s in STATE["sessions"]:
                    by_book.setdefault(s["bookId"], 0)
                    by_book[s["bookId"]] += int(s["durationSeconds"])
                STATE["last_timeline_query"] = u.query
                return self._json(200, [{"bookId": b, "bookTitle": "?", "totalSessions": 1, "totalDurationSeconds": d} for b, d in by_book.items()])
            if what == "heatmap/monthly":
                return self._json(200, [{"date": d, "count": sum(1 for s in STATE["sessions"] if s["startTime"][:10] == d)} for d in days])
            if what == "completion-timeline":
                return self._json(200, [{"year": 2026, "month": 10, "totalBooks": 3, "finishedBooks": 2}, {"year": 2026, "month": 11, "totalBooks": 1, "finishedBooks": 1}])
            return self._json(404)
        if u.path == "/api/v1/app/libraries":
            if STATE.get("lib500"):   # what the user's server does
                return self._json(500, {"message": "An unexpected error occurred.", "status": 500})
            return self._json(200, LIBRARIES)
        if u.path == "/api/v1/libraries":   # web app endpoint (no bookCount)
            return self._json(200, [{"id": l["id"], "name": l["name"], "watch": False} for l in LIBRARIES])
        if u.path == "/api/v1/app/authors":
            items = AUTHORS
            if q.get("search"):
                items = [a for a in AUTHORS if q["search"][0].lower() in a["name"].lower()]
            if q.get("sort") == ["name"]:
                items = sorted(items, key=lambda a: a["name"].lower(), reverse=q.get("dir") == ["desc"])
            return self._json(200, page_of(items, q, 30))
        if u.path == "/api/v1/app/series":
            items = sorted(SERIES, key=lambda x: x["seriesName"].lower()) if q.get("sort") == ["name"] else SERIES
            return self._json(200, page_of(items, q, 20))
        m = re.match(r"^/api/v1/epub/(\d+)/info$", u.path)   # EpubReaderController
        if m:
            if not self._user():
                return self._json(401)
            book = next((b for b in BOOKS if b["id"] == int(m.group(1))), None)
            if not book or book["primaryFileType"] != "EPUB":
                return self._json(404)
            return self._json(200, {"containerPath": "META-INF/container.xml", "rootPath": "OEBPS/", "spine": [], "manifest": [],
                                    "coverPath": "OEBPS/images/cover.jpg"})
        m = re.match(r"^/api/v1/epub/(\d+)/file/(.+)$", u.path)
        if m:
            if not self._user():
                return self._json(401)
            if m.group(2) != "OEBPS/images/cover.jpg":
                return self._json(404)
            data = COVER_JPEG
            self.send_response(200); self.send_header("Content-Type", "image/jpeg")
            self.send_header("Content-Length", str(len(data))); self.end_headers(); self.wfile.write(data)
            return
        m = re.match(r"^/api/v1/audiobooks/(\d+)/cover$", u.path)   # (audiobook streaming chain: CORS)
        if m:
            if not self._user():
                return self._json(401)
            data = COVER_JPEG
            self.send_response(200); self.send_header("Content-Type", "image/jpeg")
            self.send_header("Content-Length", str(len(data))); self.end_headers(); self.wfile.write(data)
            return
        m = re.match(r"^/api/v1/media/book/(\d+)/(audiobook-)?thumbnail$", u.path)
        if m:
            if not self._user():
                return self._json(401)
            book = next((b for b in BOOKS if b["id"] == int(m.group(1))), None)
            if m.group(2) and not (book and book["primaryFileType"] == "AUDIOBOOK"):
                return self._json(404)   # (only audiobooks have the square cover)
            data = COVER_JPEG
            self.send_response(200); self.send_header("Content-Type", "image/jpeg")
            self.send_header("Content-Length", str(len(data))); self.end_headers(); self.wfile.write(data)
            return
        m = re.match(r"^/api/v1/reading-sessions/book/(\d+)$", u.path)
        if m:
            if not self._user():
                return self._json(401)
            bid = int(m.group(1))
            items = [x for x in STATE["sessions"] if int(x.get("bookId") or 0) == bid]
            return self._json(200, {"content": items, "page": {"number": 0, "size": 100, "totalElements": len(items)}})
        if u.path == "/api/v1/shelves":   # ShelfService.getShelves: yours and public ones
            if not self._user():
                return self._json(401)
            return self._json(200, [shelf_dto(sid) for sid in sorted(SHELVES)
                                    if SHELF_INFO[sid]["userId"] == 1 or SHELF_INFO[sid]["publicShelf"]])
        if u.path == "/api/v1/app/shelves":
            return self._json(200, [{"id": 4, "name": "Kindle", "bookCount": len(SHELVES[4]), "publicShelf": False}])
        if u.path == "/api/v1/app/shelves/magic":
            return self._json(200, [{"id": 9, "name": "Unread fantasy", "publicShelf": False}])
        if u.path == "/api/v1/app/books":
            types = q.get("fileType", [])
            books = [b for b in BOOKS if not types or b["primaryFileType"] in types]
            if q.get("libraryId"):
                books = [b for b in books if b["libraryId"] == int(q["libraryId"][0])]
            if q.get("authors"):   # server lowercases both sides
                want = {a.lower() for a in q["authors"]}
                books = [b for b in books if any(a.lower() in want for a in b["authors"])]
            if q.get("series"):
                books = [b for b in books if b.get("seriesName", "").lower() == q["series"][0].lower()]
            if q.get("shelfId"):
                books = [b for b in books if b["id"] in SHELVES.get(int(q["shelfId"][0]), [])]
            if q.get("magicShelfId"):
                books = [b for b in books if b["id"] in (21, 22)]
            if q.get("search") and not STATE["old_search"]:   # title, series or an author (any case)
                ql = q["search"][0].lower().strip()
                books = [b for b in books if ql in b["title"].lower() or ql in b.get("seriesName", "").lower()
                         or any(ql in a.lower() for a in b["authors"])]
            if q.get("status"):   # read status: these are Reading (or, with cr_paused, Paused)
                want = set(q["status"])
                started = BOOKS[:5] + [BOOKS[31]] + ([BOOKS[6]] if STATE["cr_paused"] else [])
                status = "PAUSED" if STATE["cr_paused"] else "READING"
                books = [b for b in books if b in started and status in want]
                if STATE["cr_paused"]:   # BOOKS[6] read last
                    books = [dict(b, lastReadTime="2026-11-0%dT10:00:00Z" % (9 if b is BOOKS[6] else 1)) for b in books]
            if q.get("sort") == ["title"]:
                books = sorted(books, key=lambda b: b["title"].lower(), reverse=q.get("dir") == ["desc"])
            if q.get("sort") == ["seriesNumber"]:
                books = sorted(books, key=lambda b: b.get("seriesNumber") or 0)
            page, size = int(q.get("page", ["0"])[0]), int(q.get("size", ["20"])[0])
            chunk = books[page * size:(page + 1) * size]
            total_pages = -(-len(books) // size)
            return self._json(200, {"content": chunk, "page": page, "size": size, "totalElements": len(books),
                                    "totalPages": total_pages, "hasNext": page + 1 < total_pages, "hasPrevious": page > 0})
        if u.path == "/api/v1/app/books/search":
            ql = q.get("q", [""])[0].lower()
            return self._json(200, {"content": [b for b in BOOKS if ql in b["title"].lower()], "page": 0, "hasNext": False})
        m = re.match(r"^/api/v1/app/books/(\d+)$", u.path)
        if m:  # AppBookDetail (the book's page)
            book = next((b for b in BOOKS if b["id"] == int(m.group(1))), None)
            if not book:
                return self._json(404)
            out = dict(book)
            out.update({"subtitle": SUBTITLES.get(book["id"]), "description": DESCRIPTIONS.get(book["id"]) or "<p>About <i>%s</i>.</p>" % book["title"],
                        "categories": ["Fantasy", "Adventure"], "goodreadsRating": 4.12, "goodreadsReviewCount": 1234,
                        "pageCount": 320, "publisher": "Mock House", "publishedDate": "2001-05-04"})
            return self._json(200, out)
        if u.path in ("/api/v1/app/books/continue-reading", "/api/v1/app/books/recently-added"):
            if STATE["cr_paused"] and u.path.endswith("continue-reading"):
                return self._json(200, [])
            return self._json(200, BOOKS[:5] + [BOOKS[31]])
        m = re.match(r"^/api/v1/audiobooks/(\d+)/info$", u.path)
        if m:
            if not self._user():
                return self._json(401)
            bid = int(m.group(1))
            if bid == 32:  # folder-based: two tracks
                return self._json(200, {"bookId": 32, "bookFileId": 1032, "title": "Book 32", "author": "Audio Author",
                    "durationMs": 120000, "codec": "mp3", "folderBased": True, "totalSizeBytes": 2 * len(AUDIO_BYTES),
                    "tracks": [{"index": 0, "fileName": "01 Intro.mp3", "title": "Intro", "durationMs": 60000, "fileSizeBytes": len(AUDIO_BYTES), "cumulativeStartMs": 0},
                               {"index": 1, "fileName": "02 Story.mp3", "title": "Story", "durationMs": 60000, "fileSizeBytes": len(AUDIO_BYTES), "cumulativeStartMs": 60000}],
                    "chapters": []})
            return self._json(200, {"bookId": bid, "bookFileId": 1000 + bid, "title": "Book %d" % bid, "author": "Narrated",
                "durationMs": 600000, "codec": "aac", "folderBased": False, "totalSizeBytes": len(AUDIO_BYTES),
                "chapters": [{"index": 0, "title": "Opening", "startTimeMs": 0, "endTimeMs": 200000, "durationMs": 200000},
                             {"index": 1, "title": "Middle", "startTimeMs": 200000, "endTimeMs": 400000, "durationMs": 200000},
                             {"index": 2, "title": "End", "startTimeMs": 400000, "endTimeMs": 600000, "durationMs": 200000}]})
        m = re.match(r"^/api/v1/audiobooks/(\d+)(?:/track/(\d+))?/stream$", u.path)
        if m:
            if not self._user():
                return self._json(401)
            STATE["log"].append(("TRACK", m.group(1), m.group(2), self.headers.get("Range")))
            data = AUDIO_BYTES if m.group(2) is not None else M4A_BYTES
            start = 0
            rng = self.headers.get("Range")
            if rng:
                start = int(re.match(r"bytes=(\d+)-", rng).group(1))
                if start >= len(data):
                    self.send_response(416); self.send_header("Content-Length", "0"); self.end_headers(); return
                self.send_response(206)
                self.send_header("Content-Range", "bytes %d-%d/%d" % (start, len(data) - 1, len(data)))
            else:
                self.send_response(200)
            body = data[start:]
            self.send_header("Content-Type", "audio/mp4"); self.send_header("Content-Length", str(len(body))); self.end_headers()
            if STATE.get("audio_cut") and STATE["audio_cut"] > 0 and m.group(2) is None:
                STATE["audio_cut"] -= 1
                self.wfile.write(body[:len(body) // 2]); self.wfile.flush()
                self.connection.shutdown(2)  # drop the connection mid-file
                return
            self.wfile.write(body)
            return
        if u.path.startswith("/api/v1/books/") and u.path.endswith("/download"):
            data = (b"PK\x03\x04" + bytes(range(256)) * 8192)[:2 * 1024 * 1024] if STATE["dl_big"] else BOOK_BYTES
            rng = self.headers.get("Range")
            STATE["log"].append(("BOOKDL", u.path, rng))
            m = re.match(r"bytes=(\d+)-", rng or "")
            if m and int(m.group(1)) < len(data):
                start = int(m.group(1))
                self.send_response(206)
                self.send_header("Content-Range", "bytes %d-%d/%d" % (start, len(data) - 1, len(data)))
                data = data[start:]
            else:
                self.send_response(200)
            self.send_header("Content-Type", "application/epub+zip")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            chunk = 64 * 1024
            try:
                for i in range(0, len(data), chunk):
                    self.wfile.write(data[i:i + chunk]); self.wfile.flush()
                    if STATE["dl_stall"] and i >= chunk * 2:
                        time.sleep(30); return
                    if STATE["dl_slow"]:
                        time.sleep(0.15)
            except (BrokenPipeError, ConnectionResetError):
                pass
            return
        self._json(404)


if __name__ == "__main__":
    port = int(sys.argv[1])
    srv = ThreadingHTTPServer(("127.0.0.1", port), H)
    # control endpoint on port+1 to flip state from tests
    class C(BaseHTTPRequestHandler):
        def log_message(self, *a): pass
        def do_GET(self):
            u = urlparse(self.path); q = parse_qs(u.query)
            if u.path == "/set":
                for k, v in q.items():
                    STATE[k] = int(v[0]) if v[0].isdigit() else v[0] == "true"
            if u.path == "/webprogress":
                bid = int(q["book"][0])
                STATE["progress"][bid] = {"bookFileId": 1000 + bid, "positionData": q.get("cfi", [None])[0],
                                          "positionHref": q.get("href", [None])[0],
                                          "progressPercent": float(q["pct"][0]),
                                          "contentSourceProgressPercent": float(q["cpct"][0]) if "cpct" in q else None}
            if u.path == "/addbm":
                STATE["bm_next"] += 1
                STATE["bookmarks"][STATE["bm_next"]] = {"id": STATE["bm_next"], "bookId": int(q["book"][0]), "cfi": q.get("cfi", [None])[0], "title": q.get("title", ["web"])[0]}
            if u.path == "/addan":
                STATE["an_next"] += 1
                STATE["annotations"][STATE["an_next"]] = {"id": STATE["an_next"], "bookId": int(q["book"][0]), "cfi": q["cfi"][0],
                    "text": q.get("text", ["web text"])[0], "color": q.get("color", ["#4ADE80"])[0], "style": "highlight",
                    "note": q.get("note", [None])[0], "chapterTitle": "Web", "createdAt": "2026-10-29T09:00:00", "updatedAt": "2026-10-29T09:00:00"}
            if u.path == "/editan":
                a = STATE["annotations"][int(q["id"][0])]
                for k in ("color", "note"):
                    if k in q: a[k] = q[k][0]
            if u.path == "/delan":
                STATE["annotations"].pop(int(q["id"][0]), None)
            if u.path == "/rating":  # the web reader rates a book (1-10; none: removed)
                bid = int(q["book"][0])
                if "r" in q: STATE["ratings"][bid] = int(q["r"][0])
                else: STATE["ratings"].pop(bid, None)
            if u.path == "/delbm":
                STATE["bookmarks"].pop(int(q["id"][0]), None)
            if u.path == "/shelf":  # the web app puts book on (add=) or takes it off (remove=) a shelf
                bid = int(q["book"][0])
                for sid in (int(x) for x in q.get("add", [])):
                    if bid not in SHELVES[sid]: SHELVES[sid].append(bid)
                for sid in (int(x) for x in q.get("remove", [])):
                    if bid in SHELVES[sid]: SHELVES[sid].remove(bid)
            if u.path == "/reset_ko":
                STATE["kouser"].clear()
            if u.path == "/expire_refresh":
                STATE["refresh"].clear(); STATE["access"].clear()
            body = json.dumps({"log": STATE["log"], "kouser": STATE["kouser"], "progress": {str(k): v for k, v in STATE["progress"].items()}, "sessions": STATE["sessions"], "last_put_body": STATE.get("last_put_body"), "last_oidc_origin": STATE.get("last_oidc_origin"), "refresh_calls": STATE["refresh_calls"], "gzip_replies": STATE.get("gzip_replies", 0), "bookmarks": list(STATE["bookmarks"].values()), "annotations": sorted(STATE["annotations"].values(), key=lambda a: a["id"]), "usage": STATE.get("usage", []), "last_timeline_query": STATE.get("last_timeline_query"), "ratings": {str(k): v for k, v in STATE["ratings"].items()}, "shelves": {str(k): v for k, v in SHELVES.items()}, "last_shelves_body": STATE.get("last_shelves_body")}).encode()
            self.send_response(200); self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)
    ctl = ThreadingHTTPServer(("127.0.0.1", port + 1), C)
    threading.Thread(target=ctl.serve_forever, daemon=True).start()
    print("ready", flush=True)
    srv.serve_forever()
