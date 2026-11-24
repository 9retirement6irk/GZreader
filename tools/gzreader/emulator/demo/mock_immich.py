"""A small Immich server for the tests (gzreader_immich.lua, the setup page, the sync page).

Mirrors the parts of Immich's API (v1.1xx to 3.x, under /api) GZreader uses:
  GET  /api/users/me
  GET  /api/albums                 ?shared=true: the albums shared with you
  GET  /api/albums/<id>            with its assets only with --old (Immich up to 2.x)
  POST /api/search/metadata        {albumIds, type, size, page} -> {assets: {items, nextPage}}
                                   ({visibility: "timeline"} without albumIds: every photo, as the timeline)
                                   (404 with --old: a server without album search)
  GET  /api/assets/<id>/thumbnail  ?size=preview: a PNG picture (Immich's are JPEG or WebP)
Single sign-on (Immich's OAuth), with a stand-in identity provider at /idp:
  GET  /api/server/features        {oauth}
  GET  /api/server/config          {oauthButtonText}
  POST /api/oauth/authorize        {redirectUri, state, codeChallenge} -> {url} (the provider's sign-in)
  GET  /idp/authorize              the provider: back to redirect_uri with ?code&state (or ?error)
  POST /api/oauth/callback         {url, state, codeVerifier} -> {accessToken} (a session)
  POST /api/api-keys               "Authorization: Bearer <session>" {name, permissions} -> {secret}
  POST /api/auth/logout            ends the session
A key made that way works as "x-api-key" with the permissions it was given.
Sign-in: "x-api-key: <key>". KEY reads everything; LIMITED_KEY has no
album.read (403), as an API key made with too few permissions; ALBUM_KEY
has what GZreader needs (album.read, asset.read, asset.view) but no
user.read.
CORS: only with --cors (Immich sends none; a proxy in front has to): the
Origin is let in, preflights answered.

  python3 -I mock_immich.py PORT [--cors] [--old]

Test helpers: GET /__state (requests seen, without keys or sign-in secrets; the
API keys made, by name and permissions; sessions open and ended), POST /__reset,
POST /__set {oauth, pkce, deny, refuse_keys} (single sign-on off; a provider
without PKCE; a sign-in cancelled at the provider; API keys refused).
"""
import base64, hashlib, json, secrets, struct, sys, threading, zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs, urlencode

KEY = "immich-test-key"
LIMITED_KEY = "immich-limited-key"
ALBUM_KEY = "immich-album-key"
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 0
CORS = "--cors" in sys.argv
OLD = "--old" in sys.argv

LOCK = threading.Lock()
STATE = {"log": [], "oauth": True, "pkce": True, "deny": False, "refuse_keys": False,
         "made": [], "sessions_open": 0, "sessions_ended": 0}
# (sign-in secrets, never in /__state)
CODES = {}     # the provider's code -> {challenge, redirect_uri, state}
SESSIONS = {}  # a session's token -> True while it's open
MADE = {}      # an API key made over a session -> its permissions
NEEDS = {"/api/users/me": "user.read", "/api/albums": "album.read", "/api/search/metadata": "asset.read"}


def uid(n, kind="a"):
    # (a UUID made from a number: 'a' for assets, 'b' for albums)
    return "%08x-0000-4000-8000-%s%011x" % (n, kind, n)


def png(w, h, shade):
    """A test picture in colour (a black frame, stripes of a shade of its own in red
    and blue), as a PNG: a colour Kindle keeps its colours, the others make it grey."""
    rows = bytearray()
    for y in range(h):
        rows.append(0)
        for x in range(w):
            edge = x < 3 or y < 3 or x >= w - 3 or y >= h - 3
            if edge:
                rows += bytes((0, 0, 0))
            elif (x // 16) % 2:
                rows += bytes((220, shade // 2, shade // 2))
            else:
                rows += bytes((255 - shade, 255 - shade, 230))
    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(bytes(rows))) + chunk(b"IEND", b""))


# albums: "Kindle" (30 photos), "Trip" (3 photos and a video), "Family" (shared with you, 2 photos)
ALBUMS = [
    {"id": uid(1, "b"), "albumName": "Kindle", "assets": [{"id": uid(i), "type": "IMAGE", "originalFileName": "IMG_%04d.JPG" % i,
                                                            "width": 4000, "height": 3000} for i in range(1, 31)]},
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
                                 "key": "ok" if self.headers.get("x-api-key") == KEY else ("limited" if self.headers.get("x-api-key") == LIMITED_KEY
                                         else ("album" if self.headers.get("x-api-key") == ALBUM_KEY
                                               else ("made" if self.headers.get("x-api-key") in MADE else "none")))})

    def auth(self):
        k = self.headers.get("x-api-key")
        if k in (KEY, LIMITED_KEY, ALBUM_KEY) or k in MADE:
            return k
        self.send(401, {"message": "Invalid API key", "statusCode": 401})
        return None

    def base(self):
        return "http://" + (self.headers.get("Host") or ("127.0.0.1:%d" % PORT))

    def session(self):
        a = self.headers.get("Authorization") or ""
        tok = a[7:] if a.startswith("Bearer ") else None
        if tok and SESSIONS.get(tok):
            return tok
        self.send(401, {"message": "Authentication required", "statusCode": 401})
        return None

    def lacks(self, k, path):
        need = NEEDS.get(path)
        return k in MADE and need and need not in MADE[k] and "all" not in MADE[k] and need

    def do_GET(self):
        u = urlparse(self.path)
        q = parse_qs(u.query)
        if u.path == "/__state":
            with LOCK:
                return self.send(200, STATE)
        if u.path == "/api/server/features":
            return self.send(200, {"oauth": STATE["oauth"], "oauthAutoLaunch": False, "passwordLogin": True, "search": True})
        if u.path == "/api/server/config":
            return self.send(200, {"oauthButtonText": "Login with Authentik", "loginPageMessage": "", "isInitialized": True})
        if u.path == "/idp/authorize":
            # the identity provider: Immich's client, a registered redirect address, and (when it offers PKCE) a challenge
            ru = q.get("redirect_uri", [""])[0]
            st = q.get("state", [""])[0]
            if q.get("client_id") != ["immich"] or q.get("response_type") != ["code"] or not st \
                    or (STATE["pkce"] and (q.get("code_challenge_method") != ["S256"] or not q.get("code_challenge"))):
                return self.send(400, {"error": "invalid_request"})
            if not ru.endswith("/oauth2-callback"):
                return self.send(400, ctype="text/html", raw=b"<h1>Invalid redirect URI</h1>")
            if STATE["deny"]:
                loc = ru + "?" + urlencode({"error": "access_denied", "error_description": "User cancelled", "state": st})
            else:
                code = secrets.token_hex(8)
                with LOCK:
                    CODES[code] = {"challenge": q.get("code_challenge", [None])[0], "redirect_uri": ru, "state": st}
                loc = ru + "?" + urlencode({"code": code, "state": st})
            self.send_response(302)
            self.send_header("Location", loc)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        self.note("GET", self.path)
        k = self.auth()
        if not k:
            return
        if self.lacks(k, u.path):
            return self.send(403, {"message": "Missing required permission: " + self.lacks(k, u.path)})
        if u.path == "/api/users/me":
            if k in (LIMITED_KEY, ALBUM_KEY):
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
        if u.path == "/__set":
            with LOCK:
                for name in ("oauth", "pkce", "deny", "refuse_keys"):
                    if name in (body or {}):
                        STATE[name] = bool(body[name])
            return self.send(200, {})
        if u.path in ("/api/oauth/authorize", "/api/oauth/callback", "/api/api-keys", "/api/auth/logout"):
            # (single sign-on: the log keeps which fields came, never the code, the PKCE secret or a token)
            self.note("POST", u.path, sorted(body) if isinstance(body, dict) else None)
            return self.sso(u.path, body if isinstance(body, dict) else {})
        self.note("POST", u.path, body)
        k = self.auth()
        if not k:
            return
        if self.lacks(k, u.path):
            return self.send(403, {"message": "Missing required permission: " + self.lacks(k, u.path)})
        if u.path == "/api/search/metadata":
            if OLD:
                return self.send(404, {"message": "Cannot POST /api/search/metadata"})
            if not isinstance(body, dict) or not (isinstance(body.get("albumIds"), list) or body.get("visibility") == "timeline"):
                return self.send(400, {"message": ["albumIds must be an array"]})
            size = int(body.get("size") or 250)
            page = int(body.get("page") or 1)
            items = []
            for a in (ALBUMS if body.get("visibility") == "timeline" and "albumIds" not in body else ALBUMS + SHARED):
                if "albumIds" not in body or a["id"] in body["albumIds"]:
                    items += [x for x in a["assets"] if not body.get("type") or x["type"] == body["type"]]
            chunk = items[(page - 1) * size: page * size]
            more = str(page + 1) if page * size < len(items) else None
            return self.send(200, {"albums": {"total": 0, "count": 0, "items": [], "facets": []},
                                   "assets": {"total": len(items), "count": len(chunk), "items": chunk, "facets": [], "nextPage": more}})
        return self.send(404, {"message": "Cannot POST " + u.path})

    def sso(self, path, body):
        if path == "/api/oauth/authorize":
            if not STATE["oauth"]:
                return self.send(400, {"message": "OAuth is not enabled", "statusCode": 400})
            if not isinstance(body.get("redirectUri"), str):
                return self.send(400, {"message": ["redirectUri must be a string"], "statusCode": 400})
            q = {"redirect_uri": body["redirectUri"], "scope": "openid email profile",
                 "state": body.get("state") or secrets.token_hex(8), "client_id": "immich", "response_type": "code"}
            if STATE["pkce"]:
                # (Immich sends the challenge only to a provider that lists PKCE)
                q["code_challenge"] = body.get("codeChallenge") or "made-by-immich"
                q["code_challenge_method"] = "S256"
            return self.send(201, {"url": self.base() + "/idp/authorize?" + urlencode(q)})
        if path == "/api/oauth/callback":
            if not STATE["oauth"]:
                return self.send(400, {"message": "OAuth is not enabled", "statusCode": 400})
            if not body.get("state"):
                return self.send(400, {"message": "OAuth state is missing", "statusCode": 400})
            if not body.get("codeVerifier"):
                return self.send(400, {"message": "OAuth code verifier is missing", "statusCode": 400})
            cb = urlparse(str(body.get("url") or ""))
            cq = parse_qs(cb.query)
            with LOCK:
                grant = CODES.pop(cq.get("code", [""])[0], None)
            sent = "%s://%s%s" % (cb.scheme, cb.netloc, cb.path)
            proof = base64.urlsafe_b64encode(hashlib.sha256(str(body["codeVerifier"]).encode()).digest()).decode().rstrip("=")
            if not grant or cq.get("state") != [body["state"]] or grant["state"] != body["state"] or grant["redirect_uri"] != sent \
                    or (STATE["pkce"] and grant["challenge"] != proof):
                return self.send(500, {"message": "OAuth login failed", "statusCode": 500})
            tok = secrets.token_urlsafe(24)
            with LOCK:
                SESSIONS[tok] = True
                STATE["sessions_open"] += 1
            return self.send(201, {"accessToken": tok, "userId": "u1", "userEmail": "will@example.com", "name": "Will",
                                   "isAdmin": False, "isOnboarded": True, "profileImagePath": "", "shouldChangePassword": False})
        tok = self.session()
        if not tok:
            return
        if path == "/api/api-keys":
            perms = body.get("permissions")
            if STATE["refuse_keys"]:
                return self.send(403, {"message": "Forbidden", "statusCode": 403})
            if not isinstance(perms, list) or not perms or not all(isinstance(x, str) for x in perms):
                return self.send(400, {"message": ["permissions must contain at least 1 element"], "statusCode": 400})
            secret = secrets.token_urlsafe(24)
            info = {"id": uid(len(MADE) + 1, "c"), "name": body.get("name") or "API Key", "permissions": perms,
                    "createdAt": "2026-01-01T00:00:00.000Z", "updatedAt": "2026-01-01T00:00:00.000Z"}
            with LOCK:
                MADE[secret] = perms
                STATE["made"].append({"name": info["name"], "permissions": perms})
            return self.send(201, dict(info, secret=secret, apiKey=info))
        # /api/auth/logout
        with LOCK:
            SESSIONS[tok] = False
            STATE["sessions_open"] -= 1
            STATE["sessions_ended"] += 1
        return self.send(200, {"successful": True, "redirectUri": "/auth/login?autoLaunch=0"})


ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
