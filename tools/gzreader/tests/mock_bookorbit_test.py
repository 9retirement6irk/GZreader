"""The mock BookOrbit server answers as the real one does (routes, sign-ins,
field names, refusals), so the tests built on it mean something.

    python3 -I mock_bookorbit_test.py <port>

Run by the plugin suite (run_tests.lua), which checks its last line.
"""
import hashlib, json, os, subprocess, sys, time, urllib.request, urllib.error

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 18196
HERE = os.path.dirname(os.path.abspath(__file__))
BASE = "http://127.0.0.1:%d" % PORT
USER, PASSWORD = "will-kindle", "hunter22"
KEY = "bok_" + "a1B2c3D4e5" * 4 + "f6G7h8I9j"
KO = {"x-auth-user": USER, "x-auth-key": hashlib.md5(PASSWORD.encode()).hexdigest()}
API = {"Authorization": "Bearer " + KEY}
DEV = {"deviceId": "kindle-pw3_01", "deviceModel": "Kindle Paperwhite 3", "pluginVersion": "1.35.0"}
passed = failed = 0


def check(cond, name):
    global passed, failed
    if cond:
        passed += 1
    else:
        failed += 1
        print("FAIL: " + name)


def call(method, path, headers=None, body=None, raw=False):
    data = json.dumps(body).encode() if body is not None else None
    h = dict(headers or {})
    if data is not None:
        h["Content-Type"] = "application/json"
    req = urllib.request.Request(BASE + path, data=data, method=method, headers=h)
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            code, out, hdr = r.status, r.read(), r.headers
    except urllib.error.HTTPError as e:
        code, out, hdr = e.code, e.read(), e.headers
    if raw:
        return code, out, hdr
    try:
        return code, json.loads(out) if out else None
    except ValueError:
        return code, None


proc = subprocess.Popen([sys.executable, "-I", os.path.join(HERE, "mock_bookorbit.py"), str(PORT)],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
try:
    for _ in range(50):
        try:
            call("GET", "/_mock/state")
            break
        except OSError:
            time.sleep(0.1)

    # --- the KOReader sign-in
    code, j = call("GET", "/api/v1/koreader/users/auth", KO)
    check(code == 200 and j == {"authorized": "OK", "username": USER}, "sign-in with the MD5 key")
    code, j = call("GET", "/api/v1/koreader/users/auth", {"x-auth-user": USER, "x-auth-key": PASSWORD})
    check(code == 200, "sign-in with the plain password")
    check(call("GET", "/api/v1/koreader/users/auth")[0] == 401, "no credentials: 401")
    check(call("GET", "/api/v1/koreader/users/auth", {"x-auth-user": USER, "x-auth-key": "wrong"})[0] == 401, "wrong password: 401")
    check(call("GET", "/api/v1/koreader/users/auth", API)[0] == 401, "an API key is not a KOReader sign-in")
    call("POST", "/_mock/set", body={"sync_enabled": False})
    check(call("GET", "/api/v1/koreader/users/auth", KO)[0] == 403, "sync switched off: 403")
    call("POST", "/_mock/reset")

    # --- version and capabilities
    code, j = call("GET", "/api/v1/koreader/plugin/version", KO)
    check(code == 200 and "bookmarkSync" in j["capabilities"] and j["serverVersion"], "version lists capabilities")
    call("POST", "/_mock/set", body={"capabilities": ["catalogListsV2"]})
    check(call("GET", "/api/v1/koreader/plugin/version", KO)[1]["capabilities"] == ["catalogListsV2"], "capabilities can be switched")
    call("POST", "/_mock/reset")

    # --- catalog
    code, j = call("GET", "/api/v1/koreader/plugin/catalog/root", KO)
    check(code == 200 and [i["section"] for i in j["sections"]] == ["continue-reading", "recent", "libraries", "collections",
                                                                "smart-scopes", "authors", "series", "all-books"], "catalog root")
    check(j["sections"][2]["href"].endswith("/sections/libraries") and "booksHref" in j["sections"][7], "root: lists and book links")
    code, j = call("GET", "/api/v1/koreader/plugin/catalog/sections/libraries", KO)
    check(code == 200 and j["section"] == "libraries" and j["items"][0]["title"] == "Fiction" and j["items"][0]["count"] == 3, "libraries section")
    check(j["items"][0]["id"] == "1" and "libraryId=1" in j["items"][0]["booksHref"], "libraries: id and link")
    check(call("GET", "/api/v1/koreader/plugin/catalog/sections/nope", KO)[0] == 400, "unknown section: 400")
    code, a = call("GET", "/api/v1/koreader/plugin/catalog/sections/authors", KO)
    check(a["total"] == 4 and a["items"][0]["title"] == "Ada Marsh" and a["items"][0]["authorId"] == 1, "authors section")
    check(call("GET", a["items"][0]["booksHref"], KO)[1]["total"] == 2, "an author's link lists their books")
    code, se = call("GET", "/api/v1/koreader/plugin/catalog/sections/series", KO)
    check(call("GET", se["items"][0]["booksHref"], KO)[1]["items"][0]["seriesIndex"] == 1, "a series link lists it in order")
    code, j = call("GET", "/api/v1/koreader/plugin/catalog/books?size=2&sort=title", KO)
    check(code == 200 and j["total"] == 5 and len(j["items"]) == 2 and j["hasNext"] and not j["hasPrevious"] and j["nextUrl"], "books: first page")
    check(j["items"][0]["title"] == "A Field Guide to Fog" and j["items"][0]["formats"] == ["epub"], "books: sorted by title")
    need = {"id", "title", "authors", "seriesId", "seriesName", "seriesIndex", "progressPercentage", "lastReadAt", "readStatus",
            "formats", "hasCover", "thumbnailUrl", "detailUrl", "addedAt", "updatedAt"}
    check(j["seriesSummary"] is None and set(j["items"][0]) == need, "books: the list item's fields")
    code, j = call("GET", "/api/v1/koreader/plugin/catalog/books?size=2&sort=title&page=3", KO)
    check(len(j["items"]) == 1 and not j["hasNext"] and j["hasPrevious"], "books: last page")
    check(call("GET", "/api/v1/koreader/plugin/catalog/books?libraryId=2", KO)[1]["total"] == 2, "books: by library")
    check(call("GET", "/api/v1/koreader/plugin/catalog/books?collectionId=12", KO)[1]["total"] == 2, "books: by collection")
    check(call("GET", "/api/v1/koreader/plugin/catalog/books?q=okafor", KO)[1]["total"] == 2, "books: search")
    check(call("GET", "/api/v1/koreader/plugin/catalog/books?sort=bogus", KO)[0] == 400, "books: bad sort is refused")
    check(call("GET", "/api/v1/koreader/plugin/catalog/books?size=500", KO)[0] == 400, "books: oversize page is refused")
    code, d = call("GET", "/api/v1/koreader/plugin/catalog/books/101", KO)
    f = d["files"][0]
    check(code == 200 and d["libraryName"] == "Fiction" and d["seriesName"] == "Waymarks" and f["format"] == "epub" and f["role"] == "primary" and f["downloadUrl"], "book detail (its main file is \"primary\")")
    check(call("GET", "/api/v1/koreader/plugin/catalog/books/999", KO)[0] == 404, "missing book: 404")
    code, png, hdr = call("GET", "/api/v1/koreader/plugin/catalog/books/101/thumbnail", KO, raw=True)
    check(code == 200 and png[:4] == b"\x89PNG" and hdr["Content-Type"] == "image/png", "thumbnail is a PNG")
    check(call("GET", "/api/v1/koreader/plugin/catalog/books/101/thumbnail", dict(KO, **{"If-None-Match": hdr["ETag"]}), raw=True)[0] == 304,
          "thumbnail: not changed is 304")
    code, data, hdr = call("GET", f["downloadUrl"], KO, raw=True)
    check(code == 200 and len(data) == f["sizeBytes"] and hashlib.md5(data).hexdigest() == f["fileHash"], "download gives the file")
    check(call("GET", f["downloadUrl"])[0] == 401, "download needs the sign-in")

    # --- matching and progress
    h = f["fileHash"]
    code, j = call("POST", "/api/v1/koreader/plugin/match-check", KO, dict(DEV, hashes=[h, "0" * 32]))
    check(code == 201 and j["matches"] == [{"hash": h, "bookId": 101, "bookFileId": f["id"]}] and j["libraryVersion"], "match-check")
    check(call("POST", "/api/v1/koreader/plugin/match-check", KO, {"hashes": [h]})[0] == 400, "match-check needs the device fields")
    check(call("POST", "/api/v1/koreader/plugin/match-check", KO, dict(DEV, deviceId="bad id!", hashes=[h]))[0] == 400, "bad deviceId is refused")
    check(call("POST", "/api/v1/koreader/plugin/match-check", KO, dict(DEV, hashes=["x"]))[0] == 400, "a non-MD5 hash is refused")
    code, j = call("POST", "/api/v1/koreader/plugin/progress", KO,
                   dict(DEV, items=[{"hash": h, "percentage": 0.42, "progress": "/body/DocFragment[3]/body/p[7]/text().0", "timestamp": 1790000000},
                                    {"hash": "f" * 32, "percentage": 0.1}]))
    check(code == 201 and j["results"] == [{"hash": h, "accepted": True}] and j["unmatched"] == ["f" * 32], "progress: accepted and unmatched")
    check(call("POST", "/api/v1/koreader/plugin/progress", KO, dict(DEV, items=[{"hash": h, "percentage": 42}]))[0] == 400, "progress: percentage is 0 to 1")
    code, j = call("GET", "/api/v1/koreader/syncs/progress/" + h, KO)
    check(code == 200 and j["percentage"] == 0.42 and j["progress"].startswith("/body/") and j["document"] == h
          and j["device"] == DEV["deviceModel"] and j["timestamp"] == 1790000000, "KOSync reads the position back")
    check(call("GET", "/api/v1/koreader/syncs/progress/" + "e" * 32, KO) == (200, {}), "KOSync: no position is {}")
    code, j = call("PUT", "/api/v1/koreader/syncs/progress", KO, {"document": h, "percentage": 0.5, "progress": "x", "device": "K", "device_id": "k1"})
    check(code == 200 and j["document"] == h and j["timestamp"], "KOSync writes a position")
    check(call("PUT", "/api/v1/koreader/syncs/progress", KO, {"document": "d" * 32, "percentage": 0.5})[0] == 404, "KOSync: unknown book is 404")
    d = call("GET", "/api/v1/koreader/plugin/catalog/books/101", KO)[1]
    check(d["progressPercentage"] == 50 and d["progress"]["fileId"] == f["id"] and d["readStatus"] == "reading",
          "the catalog shows the progress, out of 100")
    check(call("GET", "/api/v1/koreader/plugin/catalog/books?readStatus=reading", KO)[1]["total"] == 1, "books: by read status")

    # --- the main API: key, audiobooks
    code, j = call("GET", "/api/v1/auth/me", API)
    check(code == 200 and j["authenticationMethod"] == "api_key", "API key as Bearer")
    check(call("GET", "/api/v1/auth/me", {"X-Api-Key": KEY})[0] == 200, "API key as X-Api-Key")
    check(call("GET", "/api/v1/auth/me?api_key=" + KEY)[0] == 401, "API key in the address is refused")
    check(call("GET", "/api/v1/auth/me", {"Authorization": "Bearer bok_wrong"})[0] == 401, "wrong API key: 401")
    check(call("GET", "/api/v1/auth/me", {"Authorization": "Bearer " + KEY, "X-Api-Key": KEY[:-1] + "x"})[1]["message"] == "Conflicting credentials",
          "two keys that disagree are refused")
    call("POST", "/_mock/set", body={"api_keys_enabled": False})
    check(call("GET", "/api/v1/auth/me", API)[1].get("errorCode") == "API_KEYS_DISABLED", "API keys switched off")
    call("POST", "/_mock/set", body={"api_keys_enabled": True})
    check(call("GET", "/api/v1/auth/me", KO)[0] == 401, "a KOReader sign-in is not an API key")
    code, m = call("GET", "/api/v1/audiobooks/201/manifest", API)
    a0, a1 = m["assets"]
    check(code == 200 and m["schema"] == "bookorbit.audiobook-manifest" and len(m["revision"]) == 64 and m["totalDurationMs"] == 105000 and a0["sequence"] == 0
          and m["chapters"][1]["startMs"] == 60000 and m["chapters"][1]["assetId"] == a1["assetId"], "audiobook manifest")
    check(call("GET", "/api/v1/audiobooks/999/manifest", API)[0] == 404, "missing audiobook: 404")
    url = "/api/v1/audiobooks/201/assets/%s/content" % a0["assetId"]
    code, data, hdr = call("GET", url, API, raw=True)
    check(code == 200 and len(data) == a0["sizeBytes"] and hdr["Accept-Ranges"] == "bytes", "audio file, whole")
    code, part, hdr = call("GET", url, dict(API, Range="bytes=1000-"), raw=True)
    check(code == 206 and part == data[1000:] and hdr["Content-Range"] == "bytes 1000-%d/%d" % (len(data) - 1, len(data)), "audio file, resumed")
    check(call("GET", url, dict(API, Range="bytes=999999-"), raw=True)[0] == 416, "audio file: a range past the end is 416")
    check(call("GET", url, raw=True)[0] == 401, "audio file needs the key")

    state = "/api/v1/audiobooks/201/playback-state"
    check(call("GET", state, API, raw=True)[:2] == (200, b""), "no position yet: an empty reply")
    put = {"assetId": a1["assetId"], "positionMs": 15000, "capturedAt": "2026-11-22T10:00:00.000Z",
           "operationId": "3f2b8c1e-5a4d-4e6f-9a7b-1c2d3e4f5a6b", "baseRevision": 0, "manifestRevision": m["revision"]}
    code, j = call("PUT", state, API, put)
    check(code == 200 and j["revision"] == 1 and j["positionMs"] == 15000 and abs(j["percentage"] - 7500000 / 105000.0) < 1e-9
          and j["completed"] is False and "operationId" not in j, "position saved, out of 100")
    check(call("PUT", state, API, put)[1]["revision"] == 1, "the same operation sent twice changes nothing")
    code, j = call("PUT", state, API, dict(put, operationId="3f2b8c1e-5a4d-4e6f-9a7b-1c2d3e4f5a6c", positionMs=20000))
    check(code == 409, "a stale base revision is a conflict")
    code, j = call("PUT", state, API, dict(put, operationId="3f2b8c1e-5a4d-4e6f-9a7b-1c2d3e4f5a6c", positionMs=20000, baseRevision=1))
    check(code == 200 and j["revision"] == 2, "the next save with the new base revision")
    check(call("PUT", state, API, dict(put, manifestRevision="0" * 64, baseRevision=2, operationId="3f2b8c1e-5a4d-4e6f-9a7b-1c2d3e4f5a6d"))[0]
          == 412, "an old manifest revision is refused (412)")
    check(call("PUT", state, API, dict(put, positionMs=99000, baseRevision=2, operationId="3f2b8c1e-5a4d-4e6f-9a7b-1c2d3e4f5a6e"))[0] == 400,
          "a position past the file's end is refused")
    check(call("PUT", state, API, dict(put, assetId="aud_33333333-3333-4333-8333-333333333333", baseRevision=2,
                                       operationId="3f2b8c1e-5a4d-4e6f-9a7b-1c2d3e4f5a6f"))[0] == 400, "another book's file is refused")
    check(call("PUT", state, API, dict(put, assetId="6201"))[0] == 400, "the asset id must be aud_<uuid>")
    check(call("PUT", state, API, dict(put, positionMs=1.5))[0] == 400, "the position is whole milliseconds")
    check(call("PUT", state, API, dict(put, extra=1))[0] == 400, "unknown fields are refused")
    call("POST", "/_mock/set", body={"api_key_write": False})
    code, j = call("PUT", state, API, put)
    check(code == 403 and j["errorCode"] == "API_KEY_READ_ONLY", "a read-only key can't save a position")
    check(call("GET", state, API)[1]["revision"] == 2, "a read-only key can read it")
    call("POST", "/_mock/set", body={"api_key_write": True})
    check(call("DELETE", state, API, raw=True)[0] == 204 and call("GET", state, API, raw=True)[1] == b"", "position cleared")

    # --- finding the audiobooks, and the probe script
    q = {"sort": [{"field": "title", "dir": "asc"}], "pagination": {"page": 1, "size": 5},
         "filter": {"type": "group", "join": "AND", "rules": [{"type": "rule", "field": "format", "operator": "includesAny", "value": ["MP3"]}]}}
    code, j = call("POST", "/api/v1/books/query", API, q)
    check(code == 201 and j["total"] == 1 and j["items"][0]["id"] == 201, "books/query finds the audiobook by format")
    q["filter"]["rules"][0]["value"] = ["epub"]
    check(call("POST", "/api/v1/books/query", API, q)[1]["total"] == 0, "books/query: no audio format, no audiobook")
    check(call("POST", "/api/v1/books/query", API, {"page": 1})[0] == 400, "books/query needs sort and pagination")
    call("POST", "/_mock/set", body={"api_key_write": False})
    check(call("POST", "/api/v1/books/query", API, q)[0] == 201, "a read-only key can run books/query")
    call("POST", "/_mock/set", body={"api_key_write": True})

    call("POST", "/_mock/set", body={"seen": []})
    env = dict(os.environ, BOOKORBIT_URL=BASE, BOOKORBIT_KO_USER=USER, BOOKORBIT_KO_PASSWORD=PASSWORD, BOOKORBIT_API_KEY=KEY)
    probe = [sys.executable, "-I", os.path.join(HERE, "..", "bookorbit-probe.py")]
    r = subprocess.run(probe, env=env, capture_output=True, text=True, stdin=subprocess.DEVNULL, timeout=60)
    out = r.stdout + r.stderr
    check(r.returncode == 0 and "MISSING" not in out and "no answer" not in out, "the probe runs clean against the mock")
    check(out.count("has every field GZreader's tests use") == 4, "the probe compares four shapes")
    check("audio file (first 1 KB, resumable?)          206" in out and "2 file(s), 2 chapter(s)" in out, "the probe reaches the audiobook")
    for secret, what in ((PASSWORD, "password"), (KO["x-auth-key"], "password's MD5"), (KEY, "API key"), (USER, "user name"),
                         ("127.0.0.1", "address"), ("Long Way", "a book's title"), ("Marsh", "an author")):
        check(secret not in out, "the probe never prints the " + what)
    seen = call("GET", "/_mock/state")[1]
    check(all(m == "GET" or p in ("koreader/plugin/match-check",) for m, p in seen["seen"]) and len(seen["seen"]) > 10
          and seen["playback"] == {}, "the probe only reads")
    env["BOOKORBIT_KO_PASSWORD"] = "nope-nope"
    r = subprocess.run(probe, env=env, capture_output=True, text=True, stdin=subprocess.DEVNULL, timeout=60)
    env2 = dict(env, BOOKORBIT_URL="http://127.0.0.1:1")
    r2 = subprocess.run(probe, env=env2, capture_output=True, text=True, stdin=subprocess.DEVNULL, timeout=60)
    check(r2.returncode == 1 and "connection refused" in r2.stdout and "The sign-in wasn't tried" in r2.stdout and "127.0.0.1" not in r2.stdout,
          "the probe says why there was no answer, without the address")
    env2["BOOKORBIT_URL"] = "https://no-such-host.invalid"
    r2 = subprocess.run(probe, env=env2, capture_output=True, text=True, stdin=subprocess.DEVNULL, timeout=60)
    check(r2.returncode == 1 and "no-such-host" not in r2.stdout and "no answer" in r2.stdout, "a name that doesn't exist: said, not echoed")
    check(r.returncode == 1 and "401" in r.stdout and "nope-nope" not in r.stdout and "version" not in r.stdout, "the probe stops at a failed sign-in")

    # --- the server away
    call("POST", "/_mock/set", body={"offline": True})
    check(call("GET", "/api/v1/koreader/users/auth", KO)[0] == 503, "offline: 503")
    call("POST", "/_mock/reset")
    seen = call("GET", "/_mock/state")[1]
    check(seen["seen"] == [] and seen["progress"] == {}, "reset clears the state")
finally:
    proc.terminate()
    proc.wait(timeout=5)

print("%d passed, %d failed" % (passed, failed))
sys.exit(1 if failed else 0)
