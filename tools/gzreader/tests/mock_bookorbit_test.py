"""The mock BookOrbit server answers as the real one does (routes, sign-ins,
field names, refusals), so the tests built on it mean something.

    python3 -I mock_bookorbit_test.py <port>

Run by the plugin suite (run_tests.lua), which checks its last line.
"""
import hashlib, json, os, re, subprocess, sys, time, urllib.request, urllib.error

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

    # --- highlights: the exchange
    X = "/api/v1/koreader/plugin/annotations/exchange"
    hl = {"datetime": "2026-11-22 09:00:00", "drawer": "lighten", "color": "yellow", "text": "a line", "note": "mine",
          "chapter": "One", "pageno": 3, "posFormat": "xpointer", "pos0": "/body/DocFragment[2]/body/p[1]/text().0", "pos1": "/body/DocFragment[2]/body/p[1]/text().6"}
    k1 = hashlib.md5(("%s|%s" % (hl["datetime"], hl["pos0"])).encode()).hexdigest()
    bk = {"hash": h, "keys": [{"k": k1, "dt": hl["datetime"]}], "keysComplete": True, "sidecarState": "new", "changes": [hl]}
    code, j = call("POST", X, KO, dict(DEV, books=[bk]))
    r = j["results"][0]
    check(code == 201 and r["bookId"] == 101 and r["applied"]["created"] == 1 and r["toApply"] == {"add": [], "edit": [], "delete": []}
          and j["unmatched"] == [] and j["positionIncompatible"] == [], "a new highlight from the device is taken; nothing comes back")
    web = call("POST", "/_mock/set", body={"web_highlight": {"book": 101, "op": "add", "pos0": "/body/DocFragment[3]/body/p[2]/text().0",
                                                              "pos1": "/body/DocFragment[3]/body/p[2]/text().9", "text": "from the web", "color": "blue"}})[1]
    bk2 = dict(bk, sidecarState="known", changes=[])
    r = call("POST", X, KO, dict(DEV, books=[bk2]))[1]["results"][0]
    check(len(r["toApply"]["add"]) == 1 and r["toApply"]["add"][0]["text"] == "from the web" and r["toApply"]["add"][0]["serverId"] == web["serverId"]
          and r["applied"]["created"] == 0, "a highlight made on the web is offered to the device")
    check(len(call("POST", X, KO, dict(DEV, books=[bk2]))[1]["results"][0]["toApply"]["add"]) == 1, "…and again until the device says it has it")
    code, j = call("POST", X + "-ack", KO, dict(DEV, books=[{"hash": h, "applied": [{"serverId": web["serverId"], "version": 1, "status": "applied"}], "deleted": []}]))
    check(code == 201 and j["results"] == [{"hash": h, "acked": 1}], "the device acknowledges it")
    kw = web["key"]
    bk3 = dict(bk2, keys=[{"k": k1, "dt": hl["datetime"]}, {"k": kw, "dt": web["datetime"]}])
    check(call("POST", X, KO, dict(DEV, books=[bk3]))[1]["results"][0]["toApply"]["add"] == [], "…and it isn't offered again")
    call("POST", "/_mock/set", body={"web_highlight": {"book": 101, "op": "edit", "serverId": web["serverId"], "note": "a note added on the web"}})
    r = call("POST", X, KO, dict(DEV, books=[bk3]))[1]["results"][0]
    check(len(r["toApply"]["edit"]) == 1 and r["toApply"]["edit"][0]["key"] == kw and r["toApply"]["edit"][0]["note"] == "a note added on the web"
          and r["toApply"]["edit"][0]["version"] == 2, "an edit on the web comes as an edit, by the device's key")
    call("POST", X + "-ack", KO, dict(DEV, books=[{"hash": h, "applied": [{"serverId": web["serverId"], "version": 2, "status": "applied"}], "deleted": []}]))
    r = call("POST", X, KO, dict(DEV, books=[dict(bk3, changes=[dict(hl, note="changed on the device", datetimeUpdated="2026-11-22 13:00:00")])]))[1]["results"][0]
    check(r["applied"]["updated"] == 1 and r["toApply"]["edit"] == [], "an edit on the device is taken")
    r = call("POST", X, KO, dict(DEV, books=[dict(bk3, keys=[{"k": k1, "dt": hl["datetime"]}])]))[1]["results"][0]
    check(r["applied"]["deviceDeleted"] == 1 and r["toApply"]["delete"] == [], "a highlight gone from the device's list is deleted on the server")
    first = call("GET", "/_mock/state")[1]["annotations"]["101"][0]
    call("POST", "/_mock/set", body={"web_highlight": {"book": 101, "op": "delete", "serverId": first["serverId"]}})
    r = call("POST", X, KO, dict(DEV, books=[dict(bk3, keys=[{"k": k1, "dt": hl["datetime"]}])]))[1]["results"][0]
    check(r["toApply"]["delete"] == [{"serverId": first["serverId"], "key": k1, "datetime": hl["datetime"]}], "a delete on the web comes as a delete, by the device's key")
    call("POST", X + "-ack", KO, dict(DEV, books=[{"hash": h, "applied": [], "deleted": [{"serverId": first["serverId"], "status": "applied"}]}]))
    check(call("POST", X, KO, dict(DEV, books=[dict(bk3, keys=[])]))[1]["results"][0]["toApply"]["delete"] == [], "…once acknowledged, not again")
    other = dict(DEV, deviceId="another-kindle")
    r = call("POST", X, KO, dict(other, books=[dict(bk, changes=[], keys=[])]))[1]["results"][0]
    check(r["toApply"]["add"] == [] and r["applied"]["deviceDeleted"] == 0, "another device with a fresh copy: nothing is deleted (both were deleted already)")
    check(call("POST", X, KO, dict(DEV, books=[dict(bk, hash="f" * 32)]))[1]["unmatched"] == ["f" * 32], "a book BookOrbit doesn't have: unmatched")
    for bad, what in ((dict(hl, drawer="wavy"), "an unknown style"), (dict(hl, datetime="yesterday"), "a bad datetime"),
                      (dict(hl, posFormat="cfi"), "an unknown position format"), (dict(hl, extra=1), "an unknown field"),
                      ({k: v for k, v in hl.items() if k != "pos0"}, "no position")):
        check(call("POST", X, KO, dict(DEV, books=[dict(bk, changes=[bad])]))[0] == 400, "the exchange refuses " + what)
    check(call("POST", X, KO, dict(DEV, books=[dict(bk, keys=[{"k": "nope", "dt": hl["datetime"]}])]))[0] == 400, "the exchange refuses a bad key")
    check(call("POST", X, KO, dict(DEV, books=[]))[0] == 400 and call("POST", X, KO, {"books": [bk]})[0] == 400, "the exchange needs books and the device fields")

    # --- bookmarks: the exchange
    B = "/api/v1/koreader/plugin/bookmarks/exchange"
    bm = {"datetime": "2026-11-22 09:30:00", "pos": "/body/DocFragment[2]/body/p[4]/text().0", "pageno": 4, "chapter": "One", "note": "come back here"}
    bk1 = hashlib.md5(("%s|%s" % (bm["datetime"], bm["pos"])).encode()).hexdigest()
    mb = {"hash": h, "keys": [{"k": bk1, "dt": bm["datetime"]}], "keysComplete": True, "sidecarState": "new", "changes": [bm]}
    code, j = call("POST", B, KO, dict(DEV, books=[mb]))
    r = j["results"][0]
    check(code == 201 and r["accepted"] == 1 and r["toApply"] == {"add": [], "delete": []}, "a bookmark from the device is taken")
    check(call("POST", B, KO, dict(DEV, books=[dict(mb, sidecarState="known")]))[1]["results"][0]["duplicates"] == 1, "the same one again is a duplicate")
    wm = call("POST", "/_mock/set", body={"web_bookmark": {"book": 101, "op": "add", "pos": "/body/DocFragment[5]/body/p[1]/text().0", "pageno": 30, "title": "Five"}})[1]
    mb2 = dict(mb, sidecarState="known", changes=[])
    r = call("POST", B, KO, dict(DEV, books=[mb2]))[1]["results"][0]
    check(r["toApply"]["add"] == [{"serverId": wm["serverId"], "pos": wm["pos"], "pageno": 30, "title": "Five"}], "a bookmark made elsewhere is offered (no date: the device dates it)")
    wk = hashlib.md5(("2026-11-22 14:00:00|%s" % wm["pos"]).encode()).hexdigest()
    code, j = call("POST", B + "-ack", KO, dict(DEV, books=[{"hash": h, "applied": [{"serverId": wm["serverId"], "status": "applied", "key": wk,
                                                                                  "datetime": "2026-11-22 14:00:00", "pos": wm["pos"]}], "deleted": []}]))
    check(code == 201 and j["results"] == [{"hash": h, "acked": 1}], "the device says which key it has it under")
    mb3 = dict(mb2, keys=[{"k": bk1, "dt": bm["datetime"]}, {"k": wk, "dt": "2026-11-22 14:00:00"}])
    check(call("POST", B, KO, dict(DEV, books=[mb3]))[1]["results"][0]["toApply"]["add"] == [], "…and it isn't offered again")
    r = call("POST", B, KO, dict(DEV, books=[dict(mb3, keys=[{"k": bk1, "dt": bm["datetime"]}])]))[1]["results"][0]
    check(r["deviceDeleted"] == 1, "a bookmark gone from the device's list is deleted on the server")
    first_mark = call("GET", "/_mock/state")[1]["bookmarks"]["101"][0]
    call("POST", "/_mock/set", body={"web_bookmark": {"book": 101, "op": "delete", "serverId": first_mark["serverId"]}})
    r = call("POST", B, KO, dict(DEV, books=[dict(mb3, keys=[{"k": bk1, "dt": bm["datetime"]}])]))[1]["results"][0]
    check(r["toApply"]["delete"] == [{"serverId": first_mark["serverId"], "key": bk1, "datetime": bm["datetime"]}], "a delete elsewhere comes by the device's key")
    check(call("POST", B, KO, dict(DEV, books=[dict(mb, changes=[dict(bm, extra=1)])]))[0] == 400
          and call("POST", B, KO, dict(DEV, books=[dict(mb, changes=[{"datetime": bm["datetime"]}])]))[0] == 400, "the bookmark exchange refuses an unknown field and no place")

    # --- reading time and ratings
    P = "/api/v1/koreader/plugin/page-stats"
    ev = [{"page": 3, "startTime": 1790000100, "durationSeconds": 40, "totalPages": 240}, {"page": 4, "startTime": 1790000140, "durationSeconds": 35, "totalPages": 240}]
    code, j = call("POST", P, KO, dict(DEV, books=[{"hash": h, "bookFileId": f["id"], "events": ev}, {"hash": "e" * 32, "events": ev}]))
    check(code == 201 and j["results"] == [{"hash": h, "accepted": 2, "duplicates": 0}] and j["unmatched"] == ["e" * 32], "page rows taken; a book BookOrbit doesn't have is unmatched")
    check(call("POST", P, KO, dict(DEV, books=[{"hash": h, "events": ev}]))[1]["results"][0] == {"hash": h, "accepted": 0, "duplicates": 2}, "the same rows again are duplicates")
    for bad, what in (([dict(ev[0], durationSeconds=90000)], "a duration over a day"), ([dict(ev[0], startTime=0)], "no start time"),
                      ([dict(ev[0], page=1.5)], "a fractional page"), ([], "no events")):
        check(call("POST", P, KO, dict(DEV, books=[{"hash": h, "events": bad}]))[0] == 400, "page-stats refuses " + what)
    R = "/api/v1/koreader/plugin/catalog/books/101/rating"
    check(call("PUT", R, KO, {"rating": 4}) == (200, {"rating": 4}) and call("GET", "/api/v1/koreader/plugin/catalog/books/101", KO)[1]["rating"] == 4, "a rating set, and in the book's record")
    check(call("PUT", R, KO, {"rating": 0})[0] == 200 and call("PUT", R, KO, {"rating": 6})[0] == 400 and call("PUT", R, KO, {"stars": 3})[0] == 400
          and call("PUT", "/api/v1/koreader/plugin/catalog/books/999/rating", KO, {"rating": 3})[0] == 404, "ratings: 0 to 5, known books only")

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
    q = {"sort": [{"field": "title", "dir": "asc"}], "pagination": {"page": 0, "size": 5},
         "filter": {"type": "group", "join": "AND", "rules": [{"type": "rule", "field": "format", "operator": "includesAny", "value": ["MP3"]}]}}
    code, j = call("POST", "/api/v1/books/query", API, q)
    check(code == 201 and j["total"] == 1 and j["items"][0]["id"] == 201, "books/query finds the audiobook by format")
    q["filter"]["rules"][0]["value"] = ["epub"]
    j = call("POST", "/api/v1/books/query", API, q)[1]
    check(j["total"] == 4 and all(c["files"][0]["format"] == "epub" for c in j["items"]),
          "books/query: an ebook format finds the ebooks, no audiobook")
    q["filter"]["rules"].append({"type": "rule", "field": "genre", "operator": "includesAny", "value": ["Travel"]})
    j = call("POST", "/api/v1/books/query", API, q)[1]
    check(sorted(c["id"] for c in j["items"]) == [101, 102] and "Travel" in j["items"][0]["genres"],
          "books/query: and a genre: that genre's books, with their genres")
    check(call("POST", "/api/v1/books/query", API, {"page": 1})[0] == 400, "books/query needs sort and pagination")
    q2 = dict(q, pagination={"page": 1, "size": 5})
    check(call("POST", "/api/v1/books/query", API, q2)[1]["items"] == [], "books/query counts pages from 0: page 1 is the second")
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

    # --- collections on the main API
    code, cols = call("GET", "/api/v1/collections", API)
    check(code == 200 and [c["id"] for c in cols] == [11, 12] and cols[0]["bookCount"] == 2 and cols[0]["userId"] == 1, "collections listed with the API key")
    check(call("GET", "/api/v1/collections", KO)[0] == 401, "…not with the e-reader sign-in")
    CB = "/api/v1/collections/11/books"
    check(call("POST", CB, API, {"bookIds": [103]})[0] == 201 and call("GET", "/api/v1/koreader/plugin/catalog/books?collectionId=11", KO)[1]["total"] == 3,
          "a book added to a collection shows in the e-reader catalog")
    check(call("DELETE", CB, API, {"bookIds": [103]})[0] == 200 and call("GET", "/api/v1/koreader/plugin/catalog/books?collectionId=11", KO)[1]["total"] == 2, "…and taken off again")
    check(call("POST", CB, API, {"bookIds": []})[0] == 400 and call("POST", "/api/v1/collections/99/books", API, {"bookIds": [103]})[0] == 404, "collections: bad or unknown")
    call("POST", "/_mock/set", body={"collection_owners": {"13": 2}})
    check(call("POST", "/api/v1/collections/13/books", API, {"bookIds": [103]})[0] == 403 and len(call("GET", "/api/v1/collections", API)[1]) == 3,
          "someone else's shared collection is listed but can't be changed")
    call("POST", "/_mock/set", body={"api_key_write": False})
    check(call("POST", CB, API, {"bookIds": [103]})[1].get("errorCode") == "API_KEY_READ_ONLY", "a read-only key can't change a collection")
    call("POST", "/_mock/set", body={"api_key_write": True})

    # --- book requests on the main API
    BR = "/api/v1/book-requests"
    code, j = call("POST", BR, API, {"title": "The Salt Road", "authors": ["Ines Ward"], "mediaKind": "ebook"})
    check(code == 201 and j["subscribed"] is False and j["request"]["status"] == "pending" and j["request"]["authors"] == ["Ines Ward"], "a book requested")
    rid = j["request"]["id"]
    check(call("POST", BR, KO, {"title": "x", "mediaKind": "ebook"})[0] == 401, "…not with the e-reader sign-in")
    check(call("POST", BR, API, {"title": "", "mediaKind": "ebook"})[0] == 400 and call("POST", BR, API, {"title": "x", "mediaKind": "comic"})[0] == 400
          and call("POST", BR, API, {"title": "x", "mediaKind": "ebook", "extra": 1})[0] == 400, "requests: bad ones refused")
    code, j = call("POST", BR, API, {"title": "the salt road", "mediaKind": "ebook"})
    check(code == 201 and j["request"]["id"] == rid and j["subscribed"] is False, "asking again for the same book is the same request")
    other = call("POST", "/_mock/set", body={"add_request": {"title": "Low Tide", "mediaKind": "audiobook", "userId": 2, "status": "searching"}})[1]["id"]
    code, j = call("POST", BR, API, {"title": "Low Tide", "mediaKind": "audiobook"})
    check(code == 201 and j["request"]["id"] == other and j["subscribed"] is True and j["request"]["status"] == "searching", "someone else's request joined")
    code, j = call("GET", BR + "?page=1&limit=100", API)
    check(code == 200 and j["total"] == 2 and [r["id"] for r in j["items"]] == [other, rid], "your requests listed, newest first (the joined one too)")
    check(call("GET", BR + "?limit=500", API)[0] == 400, "requests: at most 100 a page")
    call("POST", "/_mock/set", body={"request_update": {"id": rid, "status": "rejected", "decisionNote": "Not this month"}})
    check(call("GET", BR + "/%d" % rid, API)[1]["decisionNote"] == "Not this month" and call("POST", BR + "/%d/cancel" % rid, API)[0] == 400,
          "a decided request shows its note and can't be cancelled")
    code, j = call("POST", BR, API, {"title": "The Salt Road", "mediaKind": "ebook"})
    rid2 = j["request"]["id"]
    check(code == 201 and rid2 != rid and call("POST", BR + "/%d/cancel" % rid2, API, {})[1]["status"] == "cancelled", "asked again after a no; then cancelled")
    check(call("POST", BR + "/%d/cancel" % other, API, {})[0] == 403 and call("POST", BR + "/999/cancel", API, {})[0] == 404, "someone else's can't be cancelled")
    call("POST", "/_mock/set", body={"request_permission": False})
    check(call("GET", BR, API)[0] == 403 and call("POST", BR, API, {"title": "x", "mediaKind": "ebook"})[0] == 403, "without the Request books permission: 403")
    call("POST", "/_mock/set", body={"request_permission": True, "api_key_write": False})
    check(call("GET", BR, API)[0] == 200 and call("POST", BR, API, {"title": "x", "mediaKind": "ebook"})[1].get("errorCode") == "API_KEY_READ_ONLY",
          "a read-only key lists requests but can't make one")
    call("POST", "/_mock/set", body={"api_key_write": True})

    # --- the KOReader sync sign-in through the API key
    KC = "/api/v1/koreader/credentials"
    code, j = call("GET", KC, API)
    check(code == 200 and j["username"] == "will-kindle" and j["syncEnabled"] is True and "password" not in j and "passwordMd5" not in j,
          "the sync sign-in's name with the API key (never its password)")
    check(call("GET", KC, KO)[0] == 401, "…not with the e-reader sign-in")
    check(call("POST", KC, API, {"username": "another", "password": "secret12"})[0] == 409, "a second sign-in can't be made")
    import io as _io, zipfile as _zip, hashlib as _hl
    code, raw, _h = call("GET", "/api/v1/koreader/plugin-package?origin=http%3A%2F%2Fbooks.example.com", API, raw=True)
    names = _zip.ZipFile(_io.BytesIO(raw)).namelist() if code == 200 else []
    prov = _zip.ZipFile(_io.BytesIO(raw)).read("bookorbit.koplugin/bookorbit_provision.lua").decode() if names else ""
    check(code == 200 and 'username = "will-kindle"' in prov and ('userkey = "%s"' % _hl.md5(b"hunter22").hexdigest()) in prov
          and 'server_url = "http://books.example.com"' in prov, "the preconfigured plugin download carries the sync name and key")
    check(call("GET", "/api/v1/koreader/plugin-package", API)[0] == 400, "…and needs an origin")
    call("POST", "/_mock/set", body={"ko_md5_known": False})
    check(call("GET", "/api/v1/koreader/plugin-package?origin=http%3A%2F%2Fbooks.example.com", API)[0] == 400, "an old sign-in: its key can't be handed over")
    call("POST", "/_mock/set", body={"ko_md5_known": True, "key_ko_permission": False})
    check(call("GET", KC, API)[0] == 403, "a key without the KOReader sync permission: 403")
    call("POST", "/_mock/set", body={"key_ko_permission": True, "ko_credentials": False, "ko_names_taken": ["will"]})
    code, raw, _h = call("GET", KC, API, raw=True)
    check(code == 200 and raw == b"" and call("GET", "/api/v1/koreader/users/auth", KO)[0] == 401, "no sign-in yet: an empty answer, and the old one doesn't work")
    check(call("POST", KC, API, {"username": "will", "password": "secret12"})[0] == 409 and call("POST", KC, API, {"username": "wi", "password": "secret12"})[0] == 400
          and call("POST", KC, API, {"username": "will-2", "password": "short"})[0] == 400, "making one: a taken name, a short name, a short password refused")
    check(call("POST", KC, API, {"username": "will-2", "password": "secret12"})[0] == 201
          and call("GET", "/api/v1/koreader/users/auth", {"x-auth-user": "will-2", "x-auth-key": _hl.md5(b"secret12").hexdigest()})[0] == 200
          and call("GET", KC, API)[1]["username"] == "will-2", "one made with the key signs in")
    call("POST", "/_mock/set", body={"ko_credentials": True, "ko_made": None, "ko_names_taken": []})

    # --- a browser on another site (the sync page): only when a reverse proxy lets it in
    PAGE = "https://sync.example.com"
    pre = {"Origin": PAGE, "Access-Control-Request-Method": "GET", "Access-Control-Request-Headers": "x-auth-user, x-auth-key"}
    code, raw, hdr = call("OPTIONS", "/api/v1/koreader/users/auth", pre, raw=True)
    code2, raw, hdr2 = call("GET", "/api/v1/koreader/users/auth", dict(KO, Origin=PAGE), raw=True)
    check(code == 404 and hdr.get("Access-Control-Allow-Origin") is None and code2 == 200 and hdr2.get("Access-Control-Allow-Origin") is None,
          "as BookOrbit in production: no preflight answer, no cross-origin headers")
    call("POST", "/_mock/set", body={"cors_origin": PAGE})
    code, raw, hdr = call("OPTIONS", "/api/v1/koreader/users/auth", pre, raw=True)
    code2, raw, hdr2 = call("GET", "/api/v1/koreader/users/auth", dict(KO, Origin=PAGE), raw=True)
    check(code == 204 and hdr.get("Access-Control-Allow-Origin") == PAGE and "x-auth-key" in hdr.get("Access-Control-Allow-Headers", "")
          and code2 == 200 and hdr2.get("Access-Control-Allow-Origin") == PAGE, "behind a proxy that lets the page in: preflight and requests answered for it")
    code, raw, hdr = call("OPTIONS", "/api/v1/koreader/users/auth", dict(pre, Origin="https://other.example.com"), raw=True)
    check(code == 404 and hdr.get("Access-Control-Allow-Origin") is None, "…and for no other site")
    call("POST", "/_mock/set", body={"cors_origin": None})

    # --- the reader's dashboard (stats over every device)
    code, j = call("GET", "/api/v1/koreader/plugin/catalog/dashboard", KO)
    ry = j.get("readingYear") or {}
    check(code == 200 and len(ry.get("minutes", [])) == 371 and ry["minutes"][-1] == 25 and ry["minutes"][-2] == 0 and re.match(r"^\d{4}-\d\d-\d\d$", ry["startDate"])
          and j["readingStreak"] == {"currentStreak": 1, "longestStreak": 21, "lastSevenDays": [m > 0 for m in ry["minutes"][-7:]]}
          and j["readingGoal"]["goalBooks"] == 30 and j["readingGoal"]["completedBooks"] == 12 and j["totalBooks"] >= 3
          and j["achievements"]["next"]["threshold"] == 50 and j["yearAgo"]["days"] == 9 and len(j["finishedThisYear"]) == 3
          and j["highlightOfTheDay"]["chapterTitle"] == "Chapter 3" and j["browseCounts"]["inProgress"] == 2,
          "the dashboard: streak, goal, a year of minutes per day, badges, a year ago, finished books, a highlight")
    check(call("GET", "/api/v1/koreader/plugin/catalog/dashboard", API)[0] == 401
          and call("GET", "/api/v1/koreader/plugin/catalog/dashboard?section=nope", KO)[0] == 400, "…with the e-reader sign-in only; an unknown section refused")
    call("POST", "/_mock/set", body={"goal_books": None, "achievements": False, "reading_year": False})
    code, j = call("GET", "/api/v1/koreader/plugin/catalog/dashboard", KO)
    check(code == 200 and j["readingGoal"]["goalBooks"] is None and j["achievements"] is None and "readingYear" not in j,
          "no goal, badges off, an older server: the dashboard says so")
    call("POST", "/_mock/set", body={"goal_books": 30, "achievements": True, "reading_year": True})

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
